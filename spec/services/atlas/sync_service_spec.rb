require "rails_helper"
require "tmpdir"

RSpec.describe Atlas::SyncService do
  let(:source_dir) { Dir.mktmpdir("atlas-source") }
  let(:target_dir) { Dir.mktmpdir("atlas-target") }

  after do
    FileUtils.remove_entry(source_dir)
    FileUtils.remove_entry(target_dir)
  end

  def write_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  describe ".call" do
    it "mirrors supported files into blobs and generates metadata with deduplication" do
      write_file(File.join(source_dir, "features", "doc_a.md"), "# Title A\nContent\n")
      write_file(File.join(source_dir, "features", "doc_b.md"), "# Title A\nContent\n")
      write_file(File.join(source_dir, "scripts", "script.rb"), "puts 'hello'\n")
      write_file(File.join(source_dir, "images", "logo.png"), "binary") # unsupported

      service = described_class.call(
        params: { source_root: source_dir, target_root: target_dir }
      )

      expect(service).to be_success
      expect(service.result[:total_documents]).to eq(3)

      blobs = Dir.glob(File.join(target_dir, "blobs", "*"))
      expect(blobs.count).to eq(2) # doc_a/doc_b deduped, plus script.rb

      index = JSON.parse(File.read(File.join(target_dir, "index.json")))
      expect(index["total_documents"]).to eq(3)

      doc_a = index["documents"].find { |doc| doc["source_path"] == "features/doc_a.md" }
      doc_b = index["documents"].find { |doc| doc["source_path"] == "features/doc_b.md" }
      script = index["documents"].find { |doc| doc["source_path"] == "scripts/script.rb" }

      expect(doc_a["duplicate_of"]).to be_nil
      expect(doc_b["duplicate_of"]).to eq("features/doc_a.md")
      expect(doc_a["title"]).to eq("Title A")
      expect(script["title"]).to eq("script.rb")
    end

    it "returns error when source directory is missing" do
      service = described_class.call(
        params: { source_root: File.join(source_dir, "missing"), target_root: target_dir }
      )

      expect(service).not_to be_success
      expect(service.errors.full_messages.first).to include("does not exist")
    end
  end
end


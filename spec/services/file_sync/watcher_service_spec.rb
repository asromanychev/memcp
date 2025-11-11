require "rails_helper"
require "tmpdir"

RSpec.describe FileSync::WatcherService do
  let(:source_dir) { Dir.mktmpdir("file-sync-source") }
  let(:target_dir) { Dir.mktmpdir("file-sync-target") }

  after do
    FileUtils.remove_entry(source_dir)
    FileUtils.remove_entry(target_dir)
  end

  describe ".call" do
    it "copies supported files during initial sync and updates metadata" do
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "doc.md"), "# Hello")
      File.write(File.join(source_dir, "skip.png"), "binary")

      service = described_class.call(
        params: { source_root: source_dir, target_root: target_dir }
      )

      expect(service).to be_success
      expect(File.exist?(File.join(target_dir, "doc.md"))).to be(true)
      expect(File.exist?(File.join(target_dir, "skip.png"))).to be(false)

      metadata = JSON.parse(File.read(File.join(target_dir, "index.json")))
      expect(metadata.keys).to contain_exactly("doc.md")
      expect(metadata["doc.md"]["sha256"]).to be_present
    end

    it "fails when source directory is missing" do
      service = described_class.call(
        params: { source_root: File.join(source_dir, "missing"), target_root: target_dir }
      )

      expect(service).not_to be_success
      expect(service.errors.full_messages.first).to include("does not exist")
    end
  end
end


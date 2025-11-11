require "rails_helper"
require "tmpdir"

RSpec.describe FileSync::MetadataStore do
  let(:tmp_dir) { Dir.mktmpdir("metadata-store") }
  let(:index_path) { File.join(tmp_dir, "index.json") }
  let(:store) { described_class.new(index_path:) }

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  it "loads empty index when file does not exist" do
    expect(store.metadata_for("foo.md")).to be_nil
  end

  it "updates and persists metadata" do
    store.update("foo.md", { "sha256" => "abc", "size_bytes" => 10 })

    expect(store.metadata_for("foo.md")["sha256"]).to eq("abc")
    reloaded = described_class.new(index_path:)
    expect(reloaded.metadata_for("foo.md")["size_bytes"]).to eq(10)
  end

  it "deletes entries" do
    store.update("foo.md", { "sha256" => "abc" })
    store.delete("foo.md")

    expect(store.metadata_for("foo.md")).to be_nil
  end
end


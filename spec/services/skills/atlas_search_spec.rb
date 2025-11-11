require "rails_helper"

RSpec.describe Skills::AtlasSearch do
  let(:index_path) { Rails.root.join("storage/atlas/index.json") }

  before do
    Skills::Registry.clear!
    Skills::Registry.register(
      Skills::Registry::Skill.new(
        id: Skills::AtlasSearch.skill_id,
        description: Skills::AtlasSearch.description,
        parameters: Skills::AtlasSearch.parameters_schema,
        callable: Skills::AtlasSearch.method(:execute)
      )
    )

    FileUtils.mkdir_p(index_path.dirname)
    payload = {
      "documents" => [
        { "source_path" => "features/doc_a.md", "title" => "Doc A" },
        { "source_path" => "features/doc_b.md", "title" => "Something else" }
      ]
    }
    File.write(index_path, JSON.generate(payload))
  end

  after do
    FileUtils.rm_f(index_path)
    Skills::Registry.clear!
  end

  it "returns matches when query matches title" do
    result = described_class.execute(params: { query: "doc a" })

    expect(result[:errors]).to be_empty
    expect(result[:result][:matches].first["source_path"]).to eq("features/doc_a.md")
  end

  it "returns error when query blank" do
    service = described_class.call(params: { query: "" })
    expect(service).not_to be_success
    expect(service.errors.full_messages).to include("query is required")
  end
end


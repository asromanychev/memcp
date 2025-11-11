require "rails_helper"

RSpec.describe Planner::SimplePlanner do
  let(:atlas_dir) { Rails.root.join("storage/atlas") }
  let(:documents_dir) { Rails.root.join("storage/documents") }

  def register_default_skills
    Skills::Registry.clear!
    [Skills::AtlasSearch, Skills::DocumentsGrep].each do |klass|
      Skills::Registry.register(
        Skills::Registry::Skill.new(
          id: klass.skill_id,
          description: klass.description,
          parameters: klass.parameters_schema,
          callable: klass.method(:execute)
        )
      )
    end
  end

  before do
    register_default_skills

    FileUtils.mkdir_p(atlas_dir)
    File.write(
      atlas_dir.join("index.json"),
      { "documents" => [ { "source_path" => "features/demo.md", "title" => "Demo" } ] }.to_json
    )
    FileUtils.mkdir_p(documents_dir)
    File.write(documents_dir.join("demo.md"), "Demo content")
    File.write(documents_dir.join("index.json"), {}.to_json)
  end

  after do
    FileUtils.rm_rf(atlas_dir)
    FileUtils.rm_rf(documents_dir)
    register_default_skills
  end

  it "chooses atlas_search skill when query references atlas" do
    result = described_class.call(params: { query: "atlas doc" })

    expect(result).to be_success
    expect(result.result[:skill_id]).to eq("atlas_search")
  end

  it "allows explicit skill selection" do
    result = described_class.call(params: { query: "", skill_id: :documents_grep, skill_params: { pattern: "Demo" } })

    expect(result).to be_success
    expect(result.result[:skill_id]).to eq("documents_grep")
  end
end


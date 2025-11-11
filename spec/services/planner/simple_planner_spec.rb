require "rails_helper"
require "pathname"

RSpec.describe Planner::SimplePlanner do
  let(:atlas_dir) { Rails.root.join("storage/atlas") }
  let(:documents_dir) { Rails.root.join("storage/documents") }

  around do |example|
    Dir.mktmpdir("planner-observability") do |dir|
      @observability_dir = dir
      example.run
    end
  end

  let(:log_path) { Pathname(@observability_dir).join("current.jsonl") }
  let(:observability_writer) do
    Observability::Adapters::JsonlWriter.new(path: log_path, max_bytes: 1024 * 1024)
  end

  def register_default_skills
    Skills::Registry.clear!
    [ Skills::AtlasSearch, Skills::DocumentsGrep ].each do |klass|
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

    allow(Observability::Adapters::JsonlWriter).to receive(:new).and_return(observability_writer)
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

  it "emits observability events for successful execution" do
    described_class.call(params: { query: "atlas doc" })

    events = read_observability_events
    operations = events.map { |event| event["operation"] }

    expect(operations).to include("planner.start", "planner.skill_selected", "skill.execution", "planner.finish")

    skill_event = events.find { |event| event["operation"] == "skill.execution" }
    expect(skill_event["status"]).to eq("success")
    expect(skill_event["entity"]).to eq("atlas_search")
    expect(skill_event["duration_ms"]).to be_a(Float)
    expect(skill_event["extra"]).to include("result_preview")
  end

  def read_observability_events
    return [] unless log_path.exist?

    log_path.read.lines.map { |line| JSON.parse(line) }
  end
end

require "rails_helper"

RSpec.describe Memories::RecallService do
  let(:project) do
    Project.create!(
      name: "Demo",
      path: "demo",
      key: "demo"
    )
  end

  describe ".call" do
    it "returns empty result when project is not found" do
      service = described_class.call(params: { project_key: "missing" })

      expect(service).to be_success
      expect(service.result).to eq(
        facts: [],
        few_shots: [],
        links: [],
        confidence: 0.0
      )
    end

    it "filters records by scope using symbols" do
      memory = MemoryRecord.create!(
        project: project,
        content: "Scoped fact",
        kind: "fact",
        scope: %w[app services],
        tags: []
      )
      MemoryRecord.create!(
        project: project,
        content: "Other scope",
        kind: "fact",
        scope: %w[app models]
      )

      service = described_class.call(
        params: {
          project_key: project.key,
          symbols: [ "services" ]
        }
      )

      expect(service).to be_success
      texts = service.result[:facts].map { |fact| fact[:text] }
      expect(texts).to contain_exactly(memory.content)
    end

    it "filters records by tags using signals" do
      tagged = MemoryRecord.create!(
        project: project,
        content: "Tagged fact",
        kind: "fact",
        tags: %w[smoke]
      )
      MemoryRecord.create!(
        project: project,
        content: "Other tag",
        kind: "fact",
        tags: %w[other]
      )

      service = described_class.call(
        params: {
          project_key: project.key,
          signals: [ "smoke" ]
        }
      )

      expect(service).to be_success
      texts = service.result[:facts].map { |fact| fact[:text] }
      expect(texts).to contain_exactly(tagged.content)
    end

    it "skips expired memories" do
      MemoryRecord.create!(
        project: project,
        content: "Expired fact",
        kind: "fact",
        ttl: 1.day.ago
      )

      service = described_class.call(params: { project_key: project.key })

      expect(service.result[:facts]).to be_empty
    end

    it "honours limit_tokens when aggregating facts" do
      MemoryRecord.create!(
        project: project,
        content: "a" * 80,
        kind: "fact"
      )
      MemoryRecord.create!(
        project: project,
        content: "b" * 80,
        kind: "fact"
      )

      service = described_class.call(
        params: {
          project_key: project.key,
          limit_tokens: 20
        }
      )

      expect(service.result[:facts].size).to eq(1)
    end

    it "uses query for text search when provided" do
      MemoryRecord.create!(
        project: project,
        content: "Memory service smoke test",
        kind: "fact"
      )

      service = described_class.call(
        params: {
          project_key: project.key,
          query: "smoke"
        }
      )

      texts = service.result[:facts].pluck(:text)
      expect(texts).to include("Memory service smoke test")
    end
  end
end

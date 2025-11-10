require "rails_helper"

RSpec.describe Memories::RecallService do
  let(:project) { Project.create!(key: "demo", name: "Demo", path: "demo") }
  let(:vector_embedding) { Array.new(1024, 0.2) }

  describe ".call" do
    it "returns default result when project is missing" do
      service = described_class.call(params: { project_key: "unknown" })

      expect(service).to be_success
      expect(service.result).to eq(
        facts: [],
        few_shots: [],
        links: [],
        confidence: 0.0
      )
    end

    it "merges vector results ahead of text results" do
      vector_record = MemoryRecord.create!(
        project: project,
        kind: "fact",
        content: "Vector fact",
        embedding_1024: vector_embedding
      )

      text_record = MemoryRecord.create!(
        project: project,
        kind: "fact",
        content: "Text fact"
      )

      allow(Memories::EmbeddingService).to receive(:call).and_return(
        instance_double(Memories::EmbeddingService, success?: true, result: vector_embedding, errors: [])
      )

      allow_any_instance_of(described_class).to receive(:fetch_vector_records).and_return([vector_record])
      allow(MemoryRecord).to receive(:search).and_return([text_record])

      service = described_class.call(params: { project_key: project.key, query: "fact" })

      expect(service).to be_success
      expect(service.result[:facts].map { |fact| fact[:text] }).to eq(["Vector fact", "Text fact"])
    end

    it "logs a warning when embedding generation fails and falls back to text search" do
      MemoryRecord.create!(
        project: project,
        kind: "fact",
        content: "Fallback text fact"
      )

      embedding_service = instance_double(Memories::EmbeddingService, success?: false, result: [], errors: ActiveModel::Errors.new(self))
      allow(embedding_service.errors).to receive(:full_messages).and_return(["provider unavailable"])

      allow(Memories::EmbeddingService).to receive(:call).and_return(embedding_service)

      expect(Rails.logger).to receive(:warn).with(include("embedding generation failed"))

      service = described_class.call(params: { project_key: project.key, query: "fact" })

      expect(service).to be_success
      expect(service.result[:facts].map { |fact| fact[:text] }).to include("Fallback text fact")
    end

    it "adds error when project_key is missing" do
      service = described_class.call(params: { query: "fact" })

      expect(service).not_to be_success
      expect(service.errors.full_messages).to include("project_key is required")
    end
  end
end
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

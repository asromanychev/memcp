require "rails_helper"

RSpec.describe "Memory API", type: :request do
  describe "POST /save" do
    it "persists a memory and returns created response" do
      post "/save",
           params: {
             memory: {
               project_key: "demo",
               task_external_id: "T-1",
               kind: "fact",
               content: "Memory service smoke test",
               scope: %w[app services],
               tags: %w[smoke],
               owner: "ai"
             }
           },
           as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body).to include(
        "status" => "success",
        "kind" => "fact",
        "content" => "Memory service smoke test"
      )
      expect(Project.find_by(key: "demo")).to be_present
    end

    it "returns validation error when payload is incomplete" do
      post "/save",
           params: { memory: { kind: "fact" } },
           as: :json

      expect(response.status).to eq(422)
      body = JSON.parse(response.body)
      expect(body["errors"]).to include("project_key is required", "content is required")
    end
  end

  describe "POST /recall" do
    it "returns bundle composed by recall service" do
      post "/save",
           params: {
             memory: {
               project_key: "demo",
               kind: "fact",
               content: "Memory service smoke test",
               scope: %w[app services],
               tags: %w[smoke]
             }
           },
           as: :json

      post "/recall",
           params: {
             memory: {
               project_key: "demo",
               symbols: [ "services" ]
             }
           },
           as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["facts"].map { |fact| fact["text"] }).to include("Memory service smoke test")
      expect(body["confidence"]).to be >= 0.5
    end

    it "prioritizes vector matches when query is provided" do
      project = Project.create!(key: "demo", name: "demo", path: "demo")
      matching_embedding = Array.new(1024) { 0.1 }

      vector_record = MemoryRecord.create!(
        project: project,
        kind: "fact",
        content: "Vector match first",
        embedding_1024: matching_embedding
      )

      MemoryRecord.create!(
        project: project,
        kind: "fact",
        content: "Vector match first with extra detail"
      )

      embedding_service = instance_double(Memories::EmbeddingService, success?: true, result: matching_embedding, errors: [])
      allow(Memories::EmbeddingService).to receive(:call).and_return(embedding_service)
      allow_any_instance_of(Memories::RecallService).to receive(:fetch_vector_records).and_return([ vector_record ])

      post "/recall",
           params: {
             memory: {
               project_key: "demo",
               query: "Vector match"
             }
           },
           as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      fact_texts = body["facts"].map { |fact| fact["text"] }
      vector_index = fact_texts.index("Vector match first")
      fallback_index = fact_texts.index("Vector match first with extra detail")

      expect(vector_index).not_to be_nil
      expect(fallback_index).not_to be_nil
      expect(vector_index).to be < fallback_index
      expect(Memories::EmbeddingService).to have_received(:call).with(params: { content: "Vector match" })
      expect(fact_texts).to include(vector_record.content)
    end
  end
end

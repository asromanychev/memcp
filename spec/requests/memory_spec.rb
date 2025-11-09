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
  end
end

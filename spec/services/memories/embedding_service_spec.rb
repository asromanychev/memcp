require "rails_helper"

RSpec.describe Memories::EmbeddingService do
  let(:endpoint) { Memories::Embeddings.providers[:local_1024][:endpoint] }

  describe ".call" do
    it "returns embedding on successful response" do
      embedding = Array.new(1024, 0.5)

      stub_request(:post, endpoint)
        .with(
          headers: { "Content-Type" => "application/json" },
          body: { inputs: [ "embedding smoke test" ] }.to_json
        )
        .to_return(
          status: 200,
          body: { embeddings: [ embedding ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      service = described_class.call(params: { content: "embedding smoke test" })

      expect(service).to be_success
      expect(service.result).to eq(embedding)
    end

    it "returns error when content is blank" do
      service = described_class.call(params: { content: "  " })

      expect(service).not_to be_success
      expect(service.errors.full_messages).to include("content is required")
    end

    it "handles non-success HTTP responses" do
      stub_request(:post, endpoint).to_return(status: 500, body: "oops")

      service = described_class.call(params: { content: "embedding smoke test" })

      expect(service).not_to be_success
      expect(service.errors.full_messages).to include("embedding provider responded with status 500")
    end

    it "handles invalid payloads" do
      stub_request(:post, endpoint).to_return(status: 200, body: "invalid json")

      service = described_class.call(params: { content: "embedding smoke test" })

      expect(service).not_to be_success
      expect(service.errors.full_messages).to include("embedding provider returned invalid payload")
    end
  end
end

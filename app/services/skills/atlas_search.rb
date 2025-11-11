require "json"

module Skills
  class AtlasSearch < Base
    register!(
      id: :atlas_search,
      description: "Search mirrored insales_atlas documents by filename/title substring",
      parameters: {
        "query" => { type: "string", required: true },
        "limit" => { type: "integer", required: false, default: 10 }
      }
    )

    def initialize(params:)
      super()
      @query = params[:query].to_s.strip
      @limit = (params[:limit] || 10).to_i
      @index_path = Rails.root.join("storage/atlas/index.json")
      @result = { matches: [] }
    end

    private

    attr_reader :query, :limit, :index_path

    def validate_call
      errors.add(:base, "query is required") if query.blank?
      errors.add(:base, "atlas index not found") unless index_path.exist?
    end

    def perform
      index = JSON.parse(index_path.read)
      documents = Array(index["documents"])
      matches = documents
        .select { |doc| doc["source_path"].downcase.include?(query.downcase) || doc["title"].to_s.downcase.include?(query.downcase) }
        .first(limit)
      @result = { matches: matches }
    rescue JSON::ParserError
      errors.add(:base, "invalid atlas index format")
    end
  end
end


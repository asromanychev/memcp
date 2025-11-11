require "json"
require "fileutils"

module FileSync
  class MetadataStore
    def initialize(index_path:)
      @index_path = Pathname(index_path)
      @data = load_index
    end

    def metadata_for(relative_path)
      data[relative_path.to_s]
    end

    def update(relative_path, attributes)
      data[relative_path.to_s] = attributes.merge("updated_at" => Time.current.iso8601)
      persist!
    end

    def delete(relative_path)
      data.delete(relative_path.to_s)
      persist!
    end

    private

    attr_reader :index_path, :data

    def load_index
      return {} unless index_path.exist?

      JSON.parse(index_path.read)
    rescue JSON::ParserError
      {}
    end

    def persist!
      FileUtils.mkdir_p(index_path.dirname)
      index_path.write(JSON.pretty_generate(data))
    end
  end
end


module Skills
  class DocumentsGrep < Base
    register!(
      id: :documents_grep,
      description: "grep pattern across storage/documents mirror and return snippets",
      parameters: {
        "pattern" => { type: "string", required: true },
        "limit" => { type: "integer", required: false, default: 10 }
      }
    )

    SNIPPET_LINES = 3

    def initialize(params:)
      super()
      @pattern = params[:pattern].to_s.strip
      @limit = (params[:limit] || 10).to_i
      @root = Rails.root.join("storage/documents")
      @result = { matches: [] }
    end

    private

    attr_reader :pattern, :limit, :root

    def validate_call
      errors.add(:base, "pattern is required") if pattern.blank?
      errors.add(:base, "documents mirror not found") unless root.exist?
    end

    def perform
      matches = []
      Dir.glob(root.join("**/*")).each do |path|
        next unless File.file?(path)

        File.foreach(path).with_index do |line, index|
          next unless line.match?(Regexp.new(pattern, Regexp::IGNORECASE))

          snippet = extract_snippet(path, index)
          matches << snippet
          break if matches.size >= limit
        end
        break if matches.size >= limit
      end
      @result = { matches: matches }
    rescue RegexpError
      errors.add(:base, "invalid pattern regex")
    end

    def extract_snippet(path, hit_index)
      lines = File.readlines(path)
      start = [hit_index - SNIPPET_LINES, 0].max
      finish = [hit_index + SNIPPET_LINES, lines.size - 1].min
      {
        "file" => Pathname(path).relative_path_from(root).to_s,
        "line" => hit_index + 1,
        "snippet" => lines[start..finish].map(&:rstrip)
      }
    end
  end
end


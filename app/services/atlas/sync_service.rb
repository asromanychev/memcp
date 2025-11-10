require "json"
require "digest"
require "fileutils"

module Atlas
  class SyncService
    include ActiveModelService

    SUPPORTED_EXTENSIONS = %w[.md .mdc .pdf .txt .rb .js .sql .json .yml .yaml].freeze

    def initialize(params:)
      super()
      @source_root = Pathname(params[:source_root] || Rails.root.join("insales_atlas"))
      @target_root = Pathname(params[:target_root] || Rails.root.join("storage/atlas"))
      @documents = []
      @seen_shas = {}
    end

    private

    attr_reader :source_root, :target_root, :documents, :seen_shas

    def validate_call
      errors.add(:base, "source_root #{source_root} does not exist") unless source_root.exist?
    end

    def perform
      prepare_directories
      enumerate_files
      write_index
      @result = {
        total_documents: documents.size,
        target_root: target_root.to_s,
        index_path: index_path.to_s
      }
    rescue StandardError => e
      errors.add(:base, e.message)
    end

    def prepare_directories
      FileUtils.mkdir_p(blobs_root)
    end

    def enumerate_files
      entries = Dir.glob(source_root.join("**/*"), File::FNM_DOTMATCH).sort

      entries.each do |entry|
        next unless File.file?(entry)

        pathname = Pathname(entry)
        next unless supported_extension?(pathname.extname)
        next if hidden_path?(pathname)

        documents << build_document(pathname)
      end
    end

    def supported_extension?(ext)
      SUPPORTED_EXTENSIONS.include?(ext.downcase)
    end

    def hidden_path?(pathname)
      pathname.each_filename.any? { |segment| segment.start_with?(".") }
    end

    def build_document(pathname)
      relative_path = pathname.relative_path_from(source_root).to_s
      sha = Digest::SHA256.file(pathname).hexdigest
      blob_path = ensure_blob(pathname, sha)
      first_seen = seen_shas[sha]
      seen_shas[sha] ||= relative_path

      {
        "source_path" => relative_path,
        "sha256" => sha,
        "blob_path" => blob_path.relative_path_from(target_root).to_s,
        "size_bytes" => pathname.size,
        "duplicate_of" => first_seen,
        "category" => category_for(relative_path),
        "title" => extract_title(pathname)
      }
    end

    def ensure_blob(pathname, sha)
      ext = pathname.extname.downcase
      ext = ".bin" if ext.empty?
      blob_path = blobs_root.join("#{sha}#{ext}")
      FileUtils.cp(pathname, blob_path) unless blob_path.exist?
      blob_path
    end

    def category_for(relative_path)
      relative_path.split(File::SEPARATOR).first
    end

    def extract_title(pathname)
      ext = pathname.extname.downcase
      return pathname.basename.to_s unless %w[.md .mdc].include?(ext)

      File.foreach(pathname) do |line|
        stripped = line.strip
        next if stripped.empty?

        return stripped.sub(/^#+\s*/, "")
      end

      pathname.basename.to_s
    rescue StandardError
      pathname.basename.to_s
    end

    def write_index
      payload = {
        generated_at: Time.current.iso8601,
        source_root: source_root.to_s,
        total_documents: documents.size,
        documents: documents
      }

      File.write(index_path, JSON.pretty_generate(payload))
    end

    def blobs_root
      target_root.join("blobs")
    end

    def index_path
      target_root.join("index.json")
    end
  end
end


require "digest"
require "listen"

module FileSync
  class WatcherService
    include ActiveModelService

    SUPPORTED_EXTENSIONS = %w[.md .mdc .txt .rb .js .sql .json .yml .yaml].freeze

    def initialize(params:)
      super()
      @source_root = Pathname(params[:source_root] || Rails.root.join("documents"))
      @target_root = Pathname(params[:target_root] || Rails.root.join("storage/documents"))
      @metadata_store = MetadataStore.new(index_path: @target_root.join("index.json"))
      @listener = nil
    end

    def stop
      listener&.stop
    end

    private

    attr_reader :source_root, :target_root, :metadata_store, :listener

    def validate_call
      errors.add(:base, "source_root #{source_root} does not exist") unless source_root.exist?
    end

    def perform
      FileUtils.mkdir_p(target_root)
      initial_sync
      start_listener
      @result = { target_root: target_root.to_s }
    end

    def initial_sync
      Dir.glob(source_root.join("**/*")).each do |path|
        next unless File.file?(path)

        handle_change(Pathname(path))
      end
    end

    def start_listener
      @listener = Listen.to(source_root.to_s, only: supported_regex) do |modified, added, removed|
        Array(modified).each { |path| handle_change(Pathname(path)) }
        Array(added).each { |path| handle_change(Pathname(path)) }
        Array(removed).each { |path| handle_removed(Pathname(path)) }
      end
      listener.start
    end

    def supported_regex
      /\.(#{SUPPORTED_EXTENSIONS.map { |ext| Regexp.escape(ext.delete_prefix(".")) }.join("|")})\z/
    end

    def handle_change(pathname)
      relative_path = pathname.relative_path_from(source_root)
      return unless supported_extension?(pathname.extname)

      sha = Digest::SHA256.file(pathname).hexdigest
      destination = target_root.join(relative_path)

      FileUtils.mkdir_p(destination.dirname)
      FileUtils.cp(pathname, destination)

      metadata_store.update(
        relative_path,
        "sha256" => sha,
        "size_bytes" => pathname.size,
        "updated_at" => Time.current.iso8601
      )
    end

    def handle_removed(pathname)
      relative_path = pathname.relative_path_from(source_root)
      destination = target_root.join(relative_path)
      FileUtils.rm_f(destination)
      metadata_store.delete(relative_path)
    end

    def supported_extension?(ext)
      SUPPORTED_EXTENSIONS.include?(ext.downcase)
    end
  end
end


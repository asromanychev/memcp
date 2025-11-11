require "fileutils"
require "pathname"
require "zlib"

module Observability
  module Adapters
    class JsonlWriter
      DEFAULT_MAX_BYTES = 10 * 1024 * 1024

      def initialize(path: default_path, max_bytes: DEFAULT_MAX_BYTES, clock: -> { Time.current.utc })
        @path = Pathname(path)
        @max_bytes = max_bytes
        @clock = clock
      end

      def write(event_hash)
        payload = "#{event_hash.to_json}\n"
        ensure_directory
        rotate_if_needed(payload.bytesize)
        path.open("a") { |file| file.write(payload) }
      end

      private

      attr_reader :path, :max_bytes, :clock

      def default_path
        Rails.root.join("storage/logs/observability/current.jsonl")
      end

      def ensure_directory
        FileUtils.mkdir_p(path.dirname)
      end

      def rotate_if_needed(incoming_size)
        return unless path.exist?
        return unless (path.size + incoming_size) > max_bytes

        rotated_path = path.sub_ext(".#{timestamp}.jsonl")
        path.rename(rotated_path)
        compress(rotated_path)
      end

      def compress(rotated_path)
        gz_path = Pathname("#{rotated_path}.gz")
        Zlib::GzipWriter.open(gz_path.to_s) do |gz|
          File.open(rotated_path, "rb") do |file|
            IO.copy_stream(file, gz)
          end
        end
        FileUtils.rm_f(rotated_path)
      end

      def timestamp
        clock.call.strftime("%Y%m%dT%H%M%S")
      end
    end
  end
end


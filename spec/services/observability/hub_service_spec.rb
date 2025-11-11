require "rails_helper"

RSpec.describe Observability::HubService do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Dir.mktmpdir("observability-spec") do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  let(:log_path) { Pathname(@tmp_dir).join("current.jsonl") }

  describe ".call" do
    it "persists normalized event to jsonl file" do
      writer = build_writer(clock_values: [Time.utc(2025, 11, 11, 12, 0, 0)])

      travel_to(Time.zone.parse("2025-11-11 12:00:00 UTC")) do
        service = described_class.call(
          params: {
            event: {
              operation: "planner.start",
              trace_id: "trace-1",
              payload: { input: "demo" }
            },
            writer: writer
          }
        )

        expect(service).to be_success
      end

      data = log_path.read
      json = data.lines.map { |line| JSON.parse(line) }.first

      expect(json["trace_id"]).to eq("trace-1")
      expect(json["operation"]).to eq("planner.start")
      expect(json["event_id"]).to be_present
      expect(json["timestamp"]).to eq("2025-11-11T12:00:00.000000Z")
      expect(json["status"]).to eq("unknown")
      expect(json["payload"]).to eq("input" => "demo")
    end

    it "rotates log file when size limit exceeded" do
      clock_values = [
        Time.utc(2025, 11, 11, 12, 0, 0),
        Time.utc(2025, 11, 11, 12, 0, 1),
        Time.utc(2025, 11, 11, 12, 0, 2)
      ]
      writer = build_writer(max_bytes: 200, clock_values: clock_values)
      event = { operation: "planner.step", trace_id: "trace-1", payload: { seq: 1 } }

      travel_to(Time.zone.parse("2025-11-11 12:00:00 UTC")) do
        described_class.call(params: { event: event, writer: writer })
      end

      travel_to(Time.zone.parse("2025-11-11 12:00:01 UTC")) do
        described_class.call(
          params: { event: event.merge(payload: { seq: 2 }), writer: writer }
        )
      end

      rotated = log_path.sub_ext(".#{clock_values.first.strftime('%Y%m%dT%H%M%S')}.jsonl.gz")
      expect(rotated).to exist

      gz_data = Zlib::GzipReader.open(rotated) { |gz| gz.read }
      first_event = JSON.parse(gz_data.lines.first)
      expect(first_event["payload"]).to eq("seq" => 1)

      current_events = log_path.read.lines.map { |line| JSON.parse(line) }
      expect(current_events.size).to eq(1)
      expect(current_events.first["payload"]).to eq("seq" => 2)
    end

    it "computes duration from timestamps and wraps errors" do
      writer = build_writer(clock_values: [Time.utc(2025, 11, 11, 12, 0, 0)])
      started_at = Time.utc(2025, 11, 11, 12, 0, 0)
      finished_at = Time.utc(2025, 11, 11, 12, 0, 1.234)
      error = RuntimeError.new("boom")
      error.set_backtrace(%w[line1 line2 line3])

      travel_to(Time.zone.parse("2025-11-11 12:00:02 UTC")) do
        described_class.call(
          params: {
            event: {
              operation: "skill.failure",
              trace_id: "trace-x",
              started_at: started_at,
              finished_at: finished_at,
              error: error
            },
            writer: writer
          }
        )
      end

      json = JSON.parse(log_path.read.lines.first)
      expect(json["duration_ms"]).to eq(1234.0)
      expect(json["error"]).to include(
        "class" => "RuntimeError",
        "message" => "boom",
        "backtrace" => %w[line1 line2 line3]
      )
    end

    it "validates presence of event and operation" do
      service = described_class.call(params: { event: nil })

      expect(service).not_to be_success
      expect(service.errors.full_messages).to include("event is required")

      service = described_class.call(params: { event: {}, writer: build_writer })

      expect(service).not_to be_success
      expect(service.errors.full_messages).to include("operation is required")
    end
  end

  def build_writer(max_bytes: 10 * 1024, clock_values: [Time.utc(2025, 11, 11, 12, 0, 0)])
    values = clock_values.dup
    Observability::Adapters::JsonlWriter.new(
      path: log_path,
      max_bytes: max_bytes,
      clock: lambda {
        next_value = values.shift
        next_value || clock_values.last
      }
    )
  end
end


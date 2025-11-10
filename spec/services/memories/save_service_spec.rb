require "rails_helper"

RSpec.describe Memories::SaveService do
  let(:project_key) { "demo" }
  let(:params) do
    {
      project_key: project_key,
      task_external_id: "T-1",
      kind: "fact",
      content: "Memory service smoke test",
      scope: %w[app services],
      tags: %w[smoke]
    }
  end

  def call_service(custom_params = {})
    described_class.call(params: params.merge(custom_params))
  end

  describe ".call" do
    it "creates project on first save and returns payload" do
      service = call_service

      expect(service).to be_success
      expect(service.result).to include(
        :id,
        project_id: Project.find_by!(key: project_key).id,
        kind: "fact",
        content: "Memory service smoke test",
        scope: %w[app services],
        tags: %w[smoke]
      )
      expect(MemoryRecord.count).to eq(1)
    end

    it "reuses existing project" do
      project = Project.create!(name: "Demo", path: "demo", key: project_key)

      expect { call_service }.not_to change(Project, :count)
      expect(MemoryRecord.last.project_id).to eq(project.id)
    end

    it "validates presence of required fields" do
      service = call_service(project_key: nil, content: nil)

      expect(service).not_to be_success
      expect(service.errors.full_messages).to include("project_key is required", "content is required")
    end

    it "validates kind against whitelist" do
      service = call_service(kind: "unknown")

      expect(service).not_to be_success
      expect(service.errors.full_messages).to include("kind must be one of: #{MemoryRecord::KINDS.join(', ')}")
    end
  end
end

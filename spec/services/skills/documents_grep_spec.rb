require "rails_helper"

RSpec.describe Skills::DocumentsGrep do
  let(:documents_root) { Rails.root.join("storage/documents") }

  before do
    Skills::Registry.clear!
    Skills::Registry.register(
      Skills::Registry::Skill.new(
        id: Skills::DocumentsGrep.skill_id,
        description: Skills::DocumentsGrep.description,
        parameters: Skills::DocumentsGrep.parameters_schema,
        callable: Skills::DocumentsGrep.method(:execute)
      )
    )

    FileUtils.mkdir_p(documents_root)
    File.write(documents_root.join("note.md"), "CartSessions::Setting\nOther line")
  end

  after do
    FileUtils.rm_rf(documents_root)
    Skills::Registry.clear!
  end

  it "returns snippet with matching line" do
    result = described_class.execute(params: { pattern: "CartSessions" })

    expect(result[:errors]).to be_empty
    expect(result[:result][:matches].first["file"]).to eq("note.md")
  end

  it "returns error for invalid regex" do
    service = described_class.call(params: { pattern: "[" })
    expect(service).not_to be_success
    expect(service.errors.full_messages.last).to eq("invalid pattern regex")
  end
end


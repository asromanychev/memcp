require "rails_helper"

RSpec.describe Skills::Registry do
  after { described_class.clear! }

  it "registers and fetches skills" do
    skill = described_class::Skill.new(
      id: "demo",
      description: "Demo",
      parameters: {},
      callable: proc { }
    )
    described_class.register(skill)

    expect(described_class.fetch("demo")).to eq(skill)
    expect(described_class.all).to include(skill)
  end
end


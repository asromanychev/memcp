require "rails_helper"
require "rake"

RSpec.describe "memories:generate_embeddings" do
  include ActiveJob::TestHelper

  before(:all) do
    Rake.application.rake_require("tasks/memories")
    Rake::Task.define_task(:environment)
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    Rake::Task["memories:generate_embeddings"].reenable
  end

  after do
    clear_enqueued_jobs
  end

  it "enqueues jobs for records missing embedding_1024" do
    project = Project.create!(key: "demo", name: "Demo", path: "demo")
    record_without_embedding = MemoryRecord.create!(project:, kind: "fact", content: "Needs embedding")
    MemoryRecord.create!(project:, kind: "fact", content: "Already vectorized", embedding_1024: Array.new(1024, 0.1))

    expect do
      Rake::Task["memories:generate_embeddings"].invoke
    end.to have_enqueued_job(Memories::GenerateEmbeddingJob).with(memory_record_id: record_without_embedding.id)
  end

  it "handles empty scope without enqueueing" do
    expect do
      Rake::Task["memories:generate_embeddings"].invoke
    end.not_to have_enqueued_job(Memories::GenerateEmbeddingJob)
  end
end


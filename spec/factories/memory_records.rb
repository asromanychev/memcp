# frozen_string_literal: true

FactoryBot.define do
  factory :memory_record do
    association :project
    content { "Test memory content" }
    kind { "fact" }
    scope { [] }
    tags { [] }
    quality { {} }
    meta { {} }
    task_external_id { nil }
    owner { nil }
    ttl { nil }

    trait :with_scope do
      scope { [ "app", "services" ] }
    end

    trait :with_tags do
      tags { [ "bugfix", "unit" ] }
    end

    trait :with_ttl do
      ttl { 1.year.from_now }
    end

    trait :expired do
      ttl { 1.day.ago }
    end

    trait :fewshot do
      kind { "fewshot" }
      content { "Step 1: Do something\nStep 2: Do something else\nStep 3: Finish" }
      meta { { title: "Test Few-shot", patch_sha: "abc123" } }
    end

    trait :adr_link do
      kind { "adr_link" }
      content { "Test ADR link content" }
      meta { { title: "Test ADR", url: "https://example.com/adr/001" } }
    end
  end
end

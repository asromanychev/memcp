# frozen_string_literal: true

FactoryBot.define do
  factory :project do
    sequence(:name) { |n| "Test Project #{n}" }
    sequence(:path) { |n| "/test/project/#{n}" }
    sequence(:key) { |n| "test_project_#{n}" }
    settings { {} }
  end
end

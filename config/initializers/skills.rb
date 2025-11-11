# frozen_string_literal: true

Rails.application.config.to_prepare do
  Skills::Registry.clear!

  [
    "Skills::AtlasSearch",
    "Skills::DocumentsGrep"
  ].each do |klass|
    klass.constantize
  end
end


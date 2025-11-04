class Project < ApplicationRecord
  has_many :memory_records, dependent: :destroy

  validates :name, presence: true
  validates :path, presence: true, uniqueness: true
end

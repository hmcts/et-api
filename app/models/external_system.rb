class ExternalSystem < ApplicationRecord
  has_many :configurations, class_name: 'ExternalSystemConfiguration', dependent: :destroy, inverse_of: false

  scope :containing_office_code, ->(office_code) { where('? = ANY (office_codes)', office_code) }
  scope :exporting_claims, -> { where(export_claims: true) }

  accepts_nested_attributes_for :configurations
end

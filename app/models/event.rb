class Event < ApplicationRecord
  belongs_to :attached_to, polymorphic: true
  enum name: {
    confirmation_email_sent: 'ConfirmationEmailSent',
    claim_prepared: 'ClaimPrepared',
    claim_queued_for_export: 'ClaimQueuedForExport',
    claim_exported_to_atos_queue: 'ClaimExportedToAtosQueue',
    response_exported_to_atos_queue: 'ResponseExportedToAtosQueue'
  }
end

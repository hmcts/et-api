Rails.application.config.after_initialize do |app|
  app.event_service.subscribe('ResponseCreated', PrepareResponseHandler, async: true, in_process: false)
  app.event_service.subscribe('ResponsePreparedForAtosExport', ResponseExportHandler, async: true, in_process: false)
  app.event_service.subscribe('ResponsePrepared', ResponseEmailHandler, async: true, in_process: false)
  app.event_service.subscribe('ResponseExported', ResponseExportedHandler, async: true, in_process: false)
  app.event_service.subscribe('ClaimCreated', PrepareClaimHandler, async: true, in_process: false)
  app.event_service.subscribe('ClaimImported', PrepareImportedClaimHandler, async: true, in_process: false)
  app.event_service.subscribe('ClaimExported', ClaimExportedHandler, async: true, in_process: false)
  app.event_service.subscribe('ClaimExportFeedbackReceived', ClaimExportFeedbackReceivedHandler, async: true, in_process: false)
  app.event_service.subscribe('ResponseExportFeedbackReceived', ClaimExportFeedbackReceivedHandler, async: true, in_process: false)
  app.event_service.subscribe('ClaimPreparedForAtosExport', ClaimExportHandler, async: false, in_process: true)
  app.event_service.subscribe('BlobBuilt', BlobBuiltHandler, async: false, in_process: true)
  app.event_service.subscribe('ReferenceCreated', ReferenceCreatedHandler, async: false, in_process: true)
end

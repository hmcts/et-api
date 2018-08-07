# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CreateClaim Request', type: :request do
  # content type "multipart/form-data"
  # body params contain :-
  #   new_claim - Contains the XML data
  #   <filename> - Yes, the filename is the parameter - crazy - it includes the extension as well.  The value is then the file
  #
  # accept application/json
  #
  describe 'POST /api/v1/new-claim', db_clean: true do
    let(:errors) { [] }
    let(:default_headers) do
      {
        'Accept': 'application/json',
        'Content-Type': 'multipart/form-data'
      }
    end
    let(:json_response) { JSON.parse(response.body).with_indifferent_access }

    shared_context 'with fake sidekiq' do
      around do |example|
        begin
          original_adapter = ActiveJob::Base.queue_adapter
          ActiveJob::Base.queue_adapter = :test
          ActiveJob::Base.queue_adapter.enqueued_jobs.clear
          ActiveJob::Base.queue_adapter.performed_jobs.clear
          example.run
        ensure
          ActiveJob::Base.queue_adapter = original_adapter
        end
      end

      def run_background_jobs
        previous_value = ActiveJob::Base.queue_adapter.perform_enqueued_jobs
        ActiveJob::Base.queue_adapter.perform_enqueued_jobs = true
        ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == EventJob }.each do |job|
          job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
        end
      ensure
        ActiveJob::Base.queue_adapter.perform_enqueued_jobs = previous_value
      end
    end

    shared_context 'with setup for claims' do |xml_factory:|
      let(:xml_as_hash) { xml_factory.call }
      let(:xml_input_file) do
        Tempfile.new.tap do |f|
          f.write xml_as_hash.to_xml
          f.rewind
        end
      end
      let(:xml_input_filename) { xml_input_file.path }
      let(:input_files) do
        files = xml_as_hash.files.map(&:filename)
        files.inject({}) do |acc, filename|
          acc[filename] = File.absolute_path(File.join('..', '..', '..', 'fixtures', filename), __FILE__)
          acc
        end
      end

      before do
        stub_request(:any, /mocked_atos_server\.com/).to_rack(EtAtosFileTransfer::Engine)
      end

      let(:staging_folder) do
        EtApi::Test::StagingFolder.new url: 'http://mocked_atos_server.com',
                                       username: Rails.configuration.et_atos_api.username,
                                       password: Rails.configuration.et_atos_api.password
      end

      # A private scrubber to set expectations for the filename - replaces white space with underscores and any non word chars are removed
      scrubber = ->(text) { text.gsub(/\s/, '_').gsub(/\W/, '') }

      let(:output_filename_pdf) { "#{json_response['feeGroupReference']}_ET1_#{scrubber.call xml_as_hash.claimants.first.forename}_#{scrubber.call xml_as_hash.claimants.first.surname}.pdf" }
      let(:output_filename_txt) { "#{json_response['feeGroupReference']}_ET1_#{scrubber.call xml_as_hash.claimants.first.forename}_#{scrubber.call xml_as_hash.claimants.first.surname}.txt" }
      let(:output_filename_xml) { "#{json_response['feeGroupReference']}_ET1_#{scrubber.call xml_as_hash.claimants.first.forename}_#{scrubber.call xml_as_hash.claimants.first.surname}.xml" }
      let(:output_filename_rtf) { "#{json_response['feeGroupReference']}_ET1_Attachment_#{scrubber.call xml_as_hash.claimants.first.forename}_#{scrubber.call xml_as_hash.claimants.first.surname}.rtf" }
      let(:output_filename_additional_claimants_txt) { "#{json_response['feeGroupReference']}_ET1a_#{scrubber.call xml_as_hash.claimants.first.forename}_#{scrubber.call xml_as_hash.claimants.first.surname}.txt" }
      let(:output_filename_additional_claimants_csv) { "#{json_response['feeGroupReference']}_ET1a_#{scrubber.call xml_as_hash.claimants.first.forename}_#{scrubber.call xml_as_hash.claimants.first.surname}.csv" }

      before do
        perform_action
        force_export_now
      end

      def perform_action
        files = xml_as_hash.files.map(&:filename)
        file_params = files.inject({}) do |acc, filename|
          acc[filename] = fixture_file_upload(input_files[filename])
          acc
        end
        xml_data = File.read(xml_input_filename)
        post '/api/v1/new-claim', params: { new_claim: xml_data }.merge(file_params), headers: default_headers
      end

      def force_export_now
        ClaimsExportJob.perform_now
      end
    end

    shared_examples 'any claim variation' do
      it 'returns the correct status code' do
        # Assert - Make sure we get a 201 - to say the reference number is created
        expect(response).to have_http_status(:created)
      end

      it 'returns status of ok' do
        # Assert - make sure we get status of ok
        expect(json_response).to include status: 'ok'
      end

      it 'returns a reference number which contains 12 digits' do
        # Assert - make sure we get status of ok
        expect(json_response).to include feeGroupReference: a_string_matching(/\A\d{12}\z/)
      end

      it 'returns a valid reference number that is persisted in the database' do
        result = Claim.where(reference: json_response[:feeGroupReference]).first

        # Assert - make sure it is a claim
        expect(result).to be_an_instance_of Claim
      end

      it 'stores the pdf file with the correct filename in the landing folder' do
        # Assert - look for the correct file in the landing folder - will be async
        expect(staging_folder.all_unzipped_filenames).to include(output_filename_pdf)
      end

      it 'stores the xml file with the correct filename in the landing folder' do
        # Assert - look for the correct file in the landing folder - will be async
        expect(staging_folder.all_unzipped_filenames).to include(output_filename_xml)
      end

      it 'stores a copy of the original xml data' do
        # Assert - look for the correct file in the landing folder - will be async
        Dir.mktmpdir do |dir|
          staging_folder.extract(output_filename_xml, to: File.join(dir, output_filename_xml))
          expect(File.join(dir, output_filename_xml)).to be_an_xml_file_copy_of(xml_input_filename)
        end
      end

      it 'has the correct structure in the et1 txt file' do
        # Assert - look for the correct structure
        expect(staging_folder.et1_txt_file(output_filename_txt)).to have_correct_file_structure(errors: errors), -> { errors.join("\n") }
      end

      it 'has the primary claimant in the et1 txt file' do
        # Assert - look for the correct file in the landing folder - will be async
        #
        claimant = normalize_xml_hash(xml_as_hash.as_json)[:claimants].first
        expect(staging_folder.et1_txt_file(output_filename_txt)).to have_claimant_for(claimant, errors: errors), -> { errors.join("\n") }
      end

      it 'has the primary respondent in the et1 txt file' do
        # Assert - look for the correct file in the landing folder - will be async
        respondent = normalize_xml_hash(xml_as_hash.as_json)[:respondents][0]
        expect(staging_folder.et1_txt_file(output_filename_txt)).to have_respondent_for(respondent, errors: errors), -> { errors.join("\n") }
      end
    end

    shared_examples 'a claim with provided reference number' do
      it 'returns a reference number which matches the one provided if one was provided' do
        # Assert - make sure we get status of ok
        expect(json_response).to include feeGroupReference: xml_as_hash.fee_group_reference
      end
    end

    shared_examples 'a claim with single respondent' do
      it 'has no secondary respondents in the et1 txt file' do
        # Assert - look for the correct file in the landing folder - will be async
        expect(staging_folder.et1_txt_file(output_filename_txt)).to have_no_additional_respondents(errors: errors), -> { errors.join("\n") }
      end
    end

    shared_examples 'a claim with multiple respondents' do
      it 'has the secondary respondents in the et1 txt file' do
        # Assert - look for the correct file in the landing folder - will be async
        respondents = normalize_xml_hash(xml_as_hash.as_json)[:respondents][1..-1]
        expect(staging_folder.et1_txt_file(output_filename_txt)).to have_additional_respondents_for(respondents, errors: errors), -> { errors.join("\n") }
      end
    end

    shared_examples 'a claim with single claimant' do
      it 'states that no additional claimants have been sent in the txt file' do
        # Assert - look for the correct file in the landing folder - will be async
        expect(staging_folder.et1_txt_file(output_filename_txt)).to have_no_additional_claimants_sent(errors: errors), -> { errors.join("\n") }
      end

      it 'does not store an ET1a txt file with the correct filename in the landing folder' do
        # Assert - look for the correct file in the landing folder - will be async
        expect(staging_folder.all_unzipped_filenames).not_to include(output_filename_additional_claimants_txt)
      end
    end

    shared_examples 'a claim with multiple claimants' do
      it 'states that additional claimants have been sent in the txt file' do
        # Assert - look for the correct file in the landing folder - will be async
        expect(staging_folder.et1_txt_file(output_filename_txt)).to have_additional_claimants_sent(errors: errors), -> { errors.join("\n") }
      end

      it 'stores an ET1a txt file with the correct structure' do
        expect(staging_folder.et1a_txt_file(output_filename_additional_claimants_txt)).to have_correct_file_structure(errors: errors), -> { errors.join("\n") }
      end

      it 'stores an ET1a txt file with the correct header for the given input data' do
        claim = normalize_xml_hash(xml_as_hash.as_json)
        expect(staging_folder.et1a_txt_file(output_filename_additional_claimants_txt)).to have_header_for(claim, errors: errors), -> { errors.join("\n") }
      end

      it 'stores an ET1a txt file with all of the claimants in the correct format' do
        # Assert
        claimants = normalize_xml_hash(xml_as_hash.as_json)[:claimants][1..-1]
        expect(staging_folder.et1a_txt_file(output_filename_additional_claimants_txt)).to have_claimants_for(claimants, errors: errors), -> { errors.join("\n") }
      end
    end

    shared_examples 'a claim with no representatives' do
      it 'has no representative in the et1 txt file' do
        # Assert - look for the correct file in the landing folder - will be async
        expect(staging_folder.et1_txt_file(output_filename_txt)).to have_no_representative(errors: errors), -> { errors.join("\n") }
      end
    end

    shared_examples 'a claim with a representative' do
      it 'has the representative in the et1 txt file' do
        # Assert - look for the correct file in the landing folder - will be async
        rep = normalize_xml_hash(xml_as_hash.as_json)[:representatives].first
        expect(staging_folder.et1_txt_file(output_filename_txt)).to have_representative_for(rep, errors: errors), -> { errors.join("\n") }
      end
    end

    shared_examples 'a claim with a csv file' do
      let(:input_csv_file) { input_files[xml_as_hash.files.find { |f| f.filename.end_with?('.csv') }.filename] }

      it 'stores the csv file' do
        # Assert - look for the correct file in the landing folder - will be async
        Dir.mktmpdir do |dir|
          staging_folder.extract(output_filename_additional_claimants_csv, to: File.join(dir, output_filename_additional_claimants_csv))
          expect(File.join(dir, output_filename_additional_claimants_csv)).to be_a_file_copy_of(input_csv_file)
        end
      end
    end

    shared_examples 'a claim with an rtf file' do
      it 'stores the rtf file with the correct filename and is a copy of the original' do
        # Assert - look for the correct file in the landing folder - will be async
        Dir.mktmpdir do |dir|
          staging_folder.extract(output_filename_rtf, to: File.join(dir, output_filename_rtf))
          expect(File.join(dir, output_filename_rtf)).to be_a_file_copy_of(input_rtf_file)
        end
      end
    end

    context 'with xml for single claimant and respondent, no representatives and no reference number' do
      include_context 'with fake sidekiq'
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, number_of_claimants: 1, number_of_respondents: 1, number_of_representatives: 0, fee_group_reference: nil) }
      include_examples 'any claim variation'
      include_examples 'a claim with single claimant'
      include_examples 'a claim with single respondent'
      include_examples 'a claim with no representatives'
    end

    context 'with xml for single claimant and respondent but no representatives' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, number_of_claimants: 1, number_of_respondents: 1, number_of_representatives: 0) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with single claimant'
      include_examples 'a claim with single respondent'
      include_examples 'a claim with no representatives'
    end

    context 'with xml for multiple claimants, 1 respondent and no representatives' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, number_of_claimants: 5, number_of_respondents: 1, number_of_representatives: 0) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with multiple claimants'
      include_examples 'a claim with single respondent'
      include_examples 'a claim with no representatives'
    end

    context 'with xml for multiple claimants, single respondent and no representative - with csv file uploaded' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, :with_csv, number_of_respondents: 1, number_of_representatives: 0) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with multiple claimants'
      include_examples 'a claim with single respondent'
      include_examples 'a claim with no representatives'
      include_examples 'a claim with a csv file'
    end

    context 'with xml for single claimant, respondent and representative' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, number_of_claimants: 1, number_of_respondents: 1, number_of_representatives: 1) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with single claimant'
      include_examples 'a claim with single respondent'
      include_examples 'a claim with a representative'
    end

    context 'with xml for single claimant, respondent and representative with non alphanumerics in names' do
      factory = lambda do
        claimants = FactoryBot.build_list(:xml_claimant, 1, :mr_na_o_malley)
        respondents = FactoryBot.build_list(:xml_claim_respondent, 1, :mr_na_o_leary)
        FactoryBot.build(:xml_claim, claimants: claimants, respondents: respondents, number_of_representatives: 1)
      end

      include_context 'with setup for claims',
        xml_factory: factory
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with single claimant'
      include_examples 'a claim with single respondent'
      include_examples 'a claim with a representative'
    end

    context 'with xml for multiple claimants, 1 respondent and a representative' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, number_of_claimants: 5, number_of_respondents: 1, number_of_representatives: 1) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with multiple claimants'
      include_examples 'a claim with single respondent'
      include_examples 'a claim with a representative'
    end

    context 'with xml for multiple claimants, single respondent and representative - with csv file uploaded' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, :with_csv, number_of_respondents: 1, number_of_representatives: 1) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with multiple claimants'
      include_examples 'a claim with single respondent'
      include_examples 'a claim with a representative'
      include_examples 'a claim with a csv file'
    end

    context 'with xml for single claimant and multiple respondents but no representatives' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, number_of_claimants: 1, number_of_respondents: 3, number_of_representatives: 0) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with single claimant'
      include_examples 'a claim with multiple respondents'
      include_examples 'a claim with no representatives'
    end

    context 'with xml for multiple claimant, multiple respondents but no representatives' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, number_of_claimants: 5, number_of_respondents: 3, number_of_representatives: 0) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with multiple claimants'
      include_examples 'a claim with multiple respondents'
      include_examples 'a claim with no representatives'
    end

    context 'with xml for multiple claimant, multiple respondents but no representatives - with csv file uploaded' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, :with_csv, number_of_respondents: 3, number_of_representatives: 0) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with multiple claimants'
      include_examples 'a claim with multiple respondents'
      include_examples 'a claim with no representatives'
      include_examples 'a claim with a csv file'
    end

    context 'with xml for single claimant, multiple respondents and a representative' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, number_of_claimants: 1, number_of_respondents: 3, number_of_representatives: 1) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with single claimant'
      include_examples 'a claim with multiple respondents'
      include_examples 'a claim with a representative'
    end

    context 'with xml for multiple claimants, multiple respondents and a representative' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, number_of_claimants: 5, number_of_respondents: 3, number_of_representatives: 1) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with multiple claimants'
      include_examples 'a claim with multiple respondents'
      include_examples 'a claim with a representative'
    end

    context 'with xml for multiple claimants, multiple respondents and a representative - with csv file uploaded' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, :with_csv, number_of_respondents: 3, number_of_representatives: 1) }
      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with multiple claimants'
      include_examples 'a claim with multiple respondents'
      include_examples 'a claim with a representative'
      include_examples 'a claim with a csv file'
    end

    context 'with xml for single claimant, single respondent and representative - with rtf file uploaded' do
      include_context 'with setup for claims',
        xml_factory: -> { FactoryBot.build(:xml_claim, :with_rtf, number_of_claimants: 1, number_of_respondents: 1, number_of_representatives: 1) }
      let(:input_rtf_file) { input_files[xml_as_hash.files.find { |f| f.filename.end_with?('.rtf') }.filename] }

      include_examples 'any claim variation'
      include_examples 'a claim with provided reference number'
      include_examples 'a claim with single claimant'
      include_examples 'a claim with single respondent'
      include_examples 'a claim with a representative'
      include_examples 'a claim with an rtf file'
    end
  end
end

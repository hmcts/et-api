require 'rails_helper'

RSpec.describe UploadedFile, type: :model do
  subject(:uploaded_file) { described_class.new filename: 'anything' }

  let(:fixture_file) { Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'et1_first_last.pdf'), 'application/pdf') }

  describe '#file=' do
    it 'persists it in memory as an activestorage attachment' do
      uploaded_file.file = fixture_file

      expect(uploaded_file.file).to be_a_stored_file
    end
  end

  describe '#url' do
    context 'when using azure cloud provider' do
      include_context 'with cloud provider switching', cloud_provider: :azure_test
      it 'returns an azurite test server url as we are in test mode' do
        uploaded_file.file = fixture_file

        expect(uploaded_file.url).to start_with("#{ActiveStorage::Blob.service.blobs.generate_uri}/#{ActiveStorage::Blob.service.container}")
      end
    end
  end

  describe '#download_blob_to' do
    context 'when in azure mode' do
      include_context 'with cloud provider switching', cloud_provider: :azure_test
      it 'downloads a file to the specified location' do
        # Arrange - Setup with a fixture file and save
        uploaded_file.file = fixture_file
        uploaded_file.save

        Dir.mktmpdir do |dir|
          filename = File.join(dir, 'my_file.pdf')
          # Act - download the blob
          uploaded_file.download_blob_to filename

          # Assert - make sure its there
          expect(File.exist?(filename)).to be true
        end
      end

      it 'downloads the correct file to the specified location' do
        # Arrange - Setup with a fixture file and save
        uploaded_file.file = fixture_file
        uploaded_file.save

        Dir.mktmpdir do |dir|
          filename = File.join(dir, 'my_file.pdf')
          # Act - download the blob
          uploaded_file.download_blob_to filename

          # Assert - make sure its there
          expect(filename).to be_a_file_copy_of fixture_file.path
        end
      end
    end
  end
end

require 'rails_helper'

RSpec.describe UploadedFile, type: :model do
  subject(:uploaded_file) { described_class.new }

  let(:fixture_file) { Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'et1_first_last.pdf'), 'application/pdf') }

  describe '#file=' do
    it 'persists it in memory as an activestorage attachment' do
      uploaded_file.file = fixture_file

      expect(uploaded_file.file).to be_a_stored_file
    end
  end

  describe '#url' do
    # @TODO RST-1676 - The amazon block can be removed
    context 'using amazon cloud provider' do
      include_context 'with cloud provider switching', cloud_provider: :amazon
      it 'returns a minio test server url as we are in test mode' do
        uploaded_file.file = fixture_file

        expect(uploaded_file.url).to start_with(ActiveStorage::Blob.service.bucket.url)
      end
    end

    context 'using azure cloud provider' do
      include_context 'with cloud provider switching', cloud_provider: :azure
      it 'returns an azurite test server url as we are in test mode' do
        uploaded_file.file = fixture_file

        expect(uploaded_file.url).to start_with("#{ActiveStorage::Blob.service.blobs.generate_uri}/#{ActiveStorage::Blob.service.container}")
      end
    end
  end

  describe '#import_file_url=' do
    shared_examples 'import_file_url= examples' do
      it 'imports from a remote url' do
        # Arrange - Store a file remotely
        remote_file = create(:uploaded_file, :example_pdf)

        # Act - Import it
        uploaded_file.import_file_url = remote_file.file.service_url

        # Assert - Make sure the file is imported
        Dir.mktmpdir do |dir|
          filename = File.join(dir, 'my_file.pdf')
          # Act - download the blob
          uploaded_file.download_blob_to filename

          # Assert - make sure its a copy of the source
          expect(filename).to be_a_file_copy_of(Rails.root.join('spec', 'fixtures', 'et1_first_last.pdf'), 'application/pdf')
        end
      end
    end

    include_examples('import_file_url= examples')
  end

  describe '#import_from_key='

  describe '#download_blob_to' do
    shared_examples 'download_blob_to examples' do
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
    # @TODO RST-1676 - The amazon block can be removed and the shared examples expanded back into their only context
    context 'in amazon mode' do
      include_context 'with cloud provider switching', cloud_provider: :amazon
      include_examples 'download_blob_to examples'
    end

    context 'in azure mode' do
      include_context 'with cloud provider switching', cloud_provider: :amazon
      include_examples 'download_blob_to examples'
    end
  end
end

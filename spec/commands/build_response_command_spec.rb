require 'rails_helper'

RSpec.describe BuildResponseCommand do
  subject(:command) { described_class.new(uuid: uuid, data: data) }

  let(:uuid) { SecureRandom.uuid }
  let(:data) do
    {
      case_number: '2234567/2016'
    }
  end
  let(:root_object) { Response.new }

  describe '#apply' do
    it 'applies the data to the root object' do
      # Act
      command.apply(root_object)

      # Assert
      expect(root_object.case_number).to eql '2234567/2016'
    end

    it 'creates a new reference and stores it in the root object' do
      # Act
      command.apply(root_object)

      # Assert
      office_code = data[:case_number][0..1]
      expect(root_object.reference).to match(/\A#{office_code}\d{8}00\z/)
    end

    it 'stores the reference in the meta hash' do
      # Act
      command.apply(root_object)

      # Assert
      expect(command.meta).to include(reference: root_object.reference)

    end

    it 'adds todays datetime to the date_of_receipt' do
      # Act
      command.apply(root_object)

      # Assert
      expect(root_object.date_of_receipt).to be_within(1.minute).of(Time.zone.now)
    end

    it 'adds todays datetime to the meta[submitted_at]' do
      # Act
      command.apply(root_object)

      # Assert
      expect(command.meta[:submitted_at]).to be_within(1.minute).of(Time.zone.now)
    end
  end
end

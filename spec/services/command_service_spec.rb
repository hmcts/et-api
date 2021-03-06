require 'rails_helper'

RSpec.describe CommandService do
  subject(:service) { described_class }

  describe '.dispatch' do
    context 'with a valid command' do
      let(:command_instance) { instance_spy('DummyCommand').tap { |instance| allow(instance).to receive(:apply).and_return instance } }
      let(:command_class) { class_spy('DummyCommand', new: command_instance).as_stubbed_const }
      let(:command_response_class) { CommandService::CommandResponse }
      let(:uuid) { SecureRandom.uuid }
      let(:data) { { anything: :goes } }
      let(:root_object) { Object.new }

      before do
        command_class
      end

      it 'creates a new instance of the command with async set to true' do
        # Act - call dispatch
        service.dispatch command: 'Dummy',
                         uuid: uuid,
                         data: data,
                         root_object: root_object

        # Assert - Make sure the command class received new with the correct params
        expect(command_class).to have_received(:new).with(uuid: uuid, data: data, async: true, command: 'Dummy')
      end

      it 'creates a new instance of the command with async set to false if specified' do
        # Act - call dispatch
        service.dispatch command: 'Dummy',
                         uuid: uuid,
                         data: data,
                         root_object: root_object,
                         async: false

        # Assert - Make sure the command class received new with the correct params
        expect(command_class).to have_received(:new).with(uuid: uuid, data: data, async: false, command: 'Dummy')
      end

      it 'calls apply on the command with the root object passed in' do
        # Act - call dispatch
        service.dispatch command: 'Dummy',
                         uuid: uuid,
                         data: data,
                         root_object: root_object

        # Assert - Make sure the command instance receives apply with the root object passed
        expect(command_instance).to have_received(:apply).with(root_object, meta: {})
      end

      it 'returns a command response' do
        # Act - call dispatch
        result = service.dispatch command: 'Dummy',
                                  uuid: uuid,
                                  data: data,
                                  root_object: root_object

        # Assert - Make sure the command instance is returned
        expect(result).to be_a command_response_class
      end
    end
  end
end

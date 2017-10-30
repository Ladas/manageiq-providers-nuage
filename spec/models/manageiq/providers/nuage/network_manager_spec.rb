describe ManageIQ::Providers::Nuage::NetworkManager do
  it '.ems_type' do
    expect(described_class.ems_type).to eq('nuage_network')
  end

  it '.description' do
    expect(described_class.description).to eq('Nuage Network Manager')
  end

  context '.raw_connect' do
    before do
      @ems = FactoryGirl.create(:ems_nuage_network_with_authentication, :hostname => 'host', :port => 8000)
    end

    it 'connects over insecure channel' do
      expect(ManageIQ::Providers::Nuage::NetworkManager::VsdClient).to receive(:new).with("http://host:8000/nuage/api/", "testuser", "secret")
      @ems.connect
    end

    it 'connects over secure channel' do
      @ems.security_protocol = 'ssl-with-validation'
      expect(ManageIQ::Providers::Nuage::NetworkManager::VsdClient).to receive(:new).with("https://host:8000/nuage/api/", "testuser", "secret")
      @ems.connect
    end
  end

  context 'validation' do
    before do
      @ems = FactoryGirl.create(:ems_nuage_network_with_authentication)
    end

    it 'raises error for unsupported auth type' do
      creds = {}
      creds[:unsupported] = {:userid => "unsupported", :password => "password"}
      @ems.endpoints << Endpoint.create(:role => 'unsupported', :hostname => 'hostname', :port => 1111)
      @ems.update_authentication(creds, :save => false)
      expect do
        @ems.verify_credentials(:unsupported)
      end.to raise_error(MiqException::MiqInvalidCredentialsError)
    end

    context 'AMQP connection' do
      before do
        @conn = double
        allow(Qpid::Proton::Reactor::Container).to receive(:new).and_return(@conn)

        creds = {}
        creds[:amqp] = {:userid => "amqp_user", :password => "amqp_password"}
        @ems.endpoints << Endpoint.create(:role => 'amqp', :hostname => 'amqp_hostname', :port => '5672')
        @ems.update_authentication(creds, :save => false)
      end

      it 'verifies AMQP credentials' do
        allow(@conn).to receive(:run).and_return(true)

        expect(@ems.verify_credentials(:amqp)).to be_truthy
      end

      it 'handles connection errors' do
        allow(@conn).to receive(:run).and_raise(StandardError, 'connection error')
        expect { @ems.verify_credentials(:amqp) }.to raise_error(StandardError)
      end
    end
  end

  context 'translate_exception' do
    before do
      @ems = FactoryGirl.build(:ems_nuage_network, :hostname => "host", :ipaddress => "::1")

      creds = {:default => {:userid => "fake_user", :password => "fake_password"}}
      @ems.update_authentication(creds, :save => false)
    end

    it "preserves and logs message for unknown exceptions" do
      allow(@ems).to receive(:with_provider_connection).and_raise(StandardError, "unlikely")

      expect($log).to receive(:error).with(/unlikely/)
      expect { @ems.verify_credentials }.to raise_error(MiqException::MiqEVMLoginError, /Unexpected.*unlikely/)
    end

    it 'handles Unauthorized' do
      exception = Excon::Errors::Unauthorized.new('unauthorized')
      allow(@ems).to receive(:with_provider_connection).and_raise(exception)
      expect { @ems.verify_credentials }.to raise_error(MiqException::MiqInvalidCredentialsError, /Login failed/)
    end

    it 'handles Timeout' do
      exception = Excon::Errors::Timeout.new
      allow(@ems).to receive(:with_provider_connection).and_raise(exception)
      expect { @ems.verify_credentials }.to raise_error(MiqException::MiqUnreachableError, /Login attempt timed out/)
    end

    it 'handles SocketError' do
      exception = Excon::Errors::SocketError.new
      allow(@ems).to receive(:with_provider_connection).and_raise(exception)
      expect { @ems.verify_credentials }.to raise_error(MiqException::MiqHostError, /Socket error/)
    end

    it 'handles MiqInvalidCredentialsError' do
      exception = MiqException::MiqInvalidCredentialsError.new('invalid credentials')
      allow(@ems).to receive(:with_provider_connection).and_raise(exception)
      expect { @ems.verify_credentials }.to raise_error(MiqException::MiqInvalidCredentialsError, /invalid credentials/)
    end

    it 'handles MiqHostError' do
      exception = MiqException::MiqHostError.new('invalid host')
      allow(@ems).to receive(:with_provider_connection).and_raise(exception)
      expect { @ems.verify_credentials }.to raise_error(MiqException::MiqHostError, /invalid host/)
    end
  end

  context '#authentications_to_validate' do
    it 'only :default is validated by default' do
      ems = FactoryGirl.build(:ems_nuage_network, :hostname => "host", :ipaddress => "::1")
      creds = {:default => {:userid => "user", :password => "password"}}
      ems.update_authentication(creds, :save => false)

      expect(ems.authentications_to_validate).to eq([:default])
    end

    it 'validates :default and :amqp when both auths are given' do
      ems = FactoryGirl.build(:ems_nuage_network_with_authentication, :hostname => "host", :ipaddress => "::1")
      creds = {:amqp => {:userid => "amqp_user", :password => "amqp_password"}}
      ems.update_authentication(creds, :save => false)

      expect(ems.authentications_to_validate).to eq([:default, :amqp])
    end
  end

  context '.event_monitor_class' do
    it 'uses valid event catcher' do
      expect(ManageIQ::Providers::Nuage::NetworkManager.event_monitor_class).to eq(ManageIQ::Providers::Nuage::NetworkManager::EventCatcher)
    end
  end
end

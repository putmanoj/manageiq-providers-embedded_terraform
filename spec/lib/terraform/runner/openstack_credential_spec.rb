require 'terraform/runner'

RSpec.describe(Terraform::Runner::OpenstackCredential) do
  it ".auth_type is the correct Authentication sub-class" do
    expect(described_class.auth_type).to(eq("ManageIQ::Providers::EmbeddedTerraform::AutomationManager::OpenstackCredential"))
  end

  context "with a credential object" do
    let(:auth) { FactoryBot.create(:embedded_terraform_openstack_credential, auth_attributes) }
    let(:auth_attributes) do
      {
        :userid   => "manageiq-openstack",
        :password => "openstack_password",
        :options  => {
          :host    => "http://fat.openstacks.example.com",
          :project => "project"
        }
      }
    end

    let(:cred) { described_class.new(auth.id) }

    # Modeled off of openstack terraform provider:
    #
    #   https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs#configuration-reference
    #
    describe "#connection_parameters" do
      it "sets OS_AUTH_URL, OS_USERNAME, OS_PASSWORD and OS_TENANT_NAME" do
        expected = [
          {
            'name'    => 'OS_AUTH_URL',
            'value'   => 'http://fat.openstacks.example.com',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_USERNAME',
            'value'   => 'manageiq-openstack',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_PASSWORD',
            'value'   => 'openstack_password',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_TENANT_NAME',
            'value'   => 'project',
            'secured' => 'false',
          },
        ]
        expect(cred.connection_parameters).to(eq(expected))
      end

      it "empty data with emtpy strings" do
        auth.update!(:userid => nil, :password => nil, :options => nil)

        expected = []
        expect(cred.connection_parameters).to(eq(expected))
      end

      it "adds OS_DOMAIN_NAME,OS_REGION_NAME,OS_CACERT,OS_CERT,OS_KEY,OS_INSECURE if present" do
        auth.update!(:options => auth.options.merge(
          :domain => "domain",  :region     => "region",      :insecure  => "true",
          :cacert => "ca-cert", :clientcert => "client-cert", :clientkey => "client-key"
        ))

        expected = [
          {
            'name'    => 'OS_AUTH_URL',
            'value'   => 'http://fat.openstacks.example.com',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_USERNAME',
            'value'   => 'manageiq-openstack',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_PASSWORD',
            'value'   => 'openstack_password',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_DOMAIN_NAME',
            'value'   => 'domain',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_TENANT_NAME',
            'value'   => 'project',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_REGION_NAME',
            'value'   => 'region',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_CACERT',
            'value'   => 'ca-cert',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_CERT',
            'value'   => 'client-cert',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_KEY',
            'value'   => 'client-key',
            'secured' => 'false',
          },
          {
            'name'    => 'OS_INSECURE',
            'value'   => 'true',
            'secured' => 'false',
          },
        ]
        expect(cred.connection_parameters).to(eq(expected))
      end
    end
  end
end

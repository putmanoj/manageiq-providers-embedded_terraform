require 'terraform/runner'

RSpec.describe(Terraform::Runner::GoogleCredential) do
  it ".auth_type is the correct Authentication sub-class" do
    expect(described_class.auth_type).to(eq("ManageIQ::Providers::EmbeddedTerraform::AutomationManager::GoogleCredential"))
  end

  context "with a credential object" do
    let(:auth) { FactoryBot.create(:embedded_terraform_google_credential, auth_attributes) }
    let(:auth_attributes) do
      {
        :userid   => "manageiq@gmail.com",
        :auth_key => "key_data",
        :options  => {:project => "google_project"}
      }
    end
    let(:gce_credentials) do
      {
        "type"                        => "service_account",
        "private_key"                 => "key_data",
        "client_email"                => "manageiq@gmail.com",
        "project_id"                  => "google_project",
        "auth_uri"                    => "https://accounts.google.com/o/oauth2/auth",
        "token_uri"                   => "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url" => "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url"        => "https://www.googleapis.com/robot/v1/metadata/x509/manageiq%40gmail.com"
      }
    end

    let(:cred) { described_class.new(auth.id) }

    # Modeled off of gce teraform provider:
    #
    #   https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference
    #
    describe "#connection_parameters" do
      it "sets GOOGLE_PROJECT and GOOGLE_CREDENTIALS_FILE_PATH" do
        expected = [
          {
            'name'    => 'GOOGLE_CREDENTIALS',
            'value'   => gce_credentials.to_json,
            'secured' => 'false',
          },
          {
            'name'    => 'GOOGLE_PROJECT',
            'value'   => 'google_project',
            'secured' => 'false',
          },
        ]
        expect(cred.connection_parameters).to(eq(expected))
      end

      it "adds GOOGLE_REGION if present" do
        auth.update!(:options => auth.options.merge(:region => "google_region"))

        expected = [
          {
            'name'    => 'GOOGLE_CREDENTIALS',
            'value'   => gce_credentials.to_json,
            'secured' => 'false',
          },
          {
            'name'    => 'GOOGLE_PROJECT',
            'value'   => 'google_project',
            'secured' => 'false',
          },
          {
            'name'    => 'GOOGLE_REGION',
            'value'   => 'google_region',
            'secured' => 'false',
          },
        ]
        expect(cred.connection_parameters).to(eq(expected))
      end

      it "empty data with empty strings if missing" do
        auth.update!(:userid => nil, :auth_key => nil, :options => nil)

        gce_credentials_with_empty_data = {
          "type"                        => 'service_account',
          "private_key"                 => '',
          "client_email"                => '',
          "project_id"                  => '',
          "auth_uri"                    => 'https://accounts.google.com/o/oauth2/auth',
          "token_uri"                   => 'https://oauth2.googleapis.com/token',
          "auth_provider_x509_cert_url" => 'https://www.googleapis.com/oauth2/v1/certs'
        }

        expected = [
          {
            'name'    => 'GOOGLE_CREDENTIALS',
            'value'   => gce_credentials_with_empty_data.to_json,
            'secured' => 'false',
          },
        ]
        expect(cred.connection_parameters).to(eq(expected))
      end
    end
  end
end

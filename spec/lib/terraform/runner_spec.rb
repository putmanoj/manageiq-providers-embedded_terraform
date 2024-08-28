require 'webmock/rspec'
require 'json'

RSpec.describe(Terraform::Runner) do
  let(:embedded_terraform) { ManageIQ::Providers::EmbeddedTerraform::AutomationManager }
  let(:manager) { FactoryBot.create(:embedded_automation_manager_terraform) }

  before(:all) do
    ENV["TERRAFORM_RUNNER_TOKEN"] = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IlNodWJoYW5naSBTaW5naCIsImlhdCI6MTcwNjAwMDk0M30.46mL8RRxfHI4yveZ2wTsHyF7s2BAiU84aruHBoz2JRQ'
    @hello_world_create_response = JSON.parse(File.read(File.join(__dir__, "runner/data/responses/hello-world-create-success.json")))
    @hello_world_retrieve_response = JSON.parse(File.read(File.join(__dir__, "runner/data/responses/hello-world-retrieve-success.json")))
  end

  before do
    EmbeddedTerraformEvmSpecHelper.assign_embedded_terraform_role
  end

  describe "is .available" do
    before do
      ENV["TERRAFORM_RUNNER_URL"] = "https://1.2.3.4:7000"

      stub_request(:get, "https://1.2.3.4:7000/ready")
        .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
    end

    it "check if terraform-runner service is available" do
      expect(Terraform::Runner.available?).to(be(true))
    end
  end

  context '.run_async hello-world' do
    describe '.run_async with input_var' do
      create_stub = nil
      retrieve_stub = nil

      def verify_req(req)
        body = JSON.parse(req.body)
        expect(body["name"]).to(start_with('stack-'))
        expect(body).to(have_key('templateZipFile'))
        expect(body["parameters"]).to(eq([{"name" => "name", "value" => "New World", "secured" => "false"}]))
        expect(body["cloud_providers"]).to(eq([]))
      end

      before do
        ENV["TERRAFORM_RUNNER_URL"] = "https://1.2.3.4:7000"

        create_stub = stub_request(:post, "https://1.2.3.4:7000/api/stack/create")
                      .with { |req| verify_req(req) }
                      .to_return(
                        :status => 200,
                        :body   => @hello_world_create_response.to_json
                      )

        retrieve_stub = stub_request(:post, "https://1.2.3.4:7000/api/stack/retrieve")
                        .with(:body => hash_including({:stack_id => @hello_world_retrieve_response['stack_id']}))
                        .to_return(
                          :status => 200,
                          :body   => @hello_world_create_response.to_json
                        )
      end

      let(:input_vars) { {'name' => 'New World'} }

      it "start running hello-world terraform template" do
        async_response = Terraform::Runner.run_async(input_vars, File.join(__dir__, "runner/data/hello-world"))
        expect(create_stub).to(have_been_requested.times(1))

        response = async_response.response
        expect(retrieve_stub).to(have_been_requested.times(1))

        expect(response.status).to(eq('IN_PROGRESS'), "terraform-runner failed with:\n#{response.status}")
        expect(response.stack_id).to(eq(@hello_world_create_response['stack_id']))
        expect(response.action).to(eq('CREATE'))
        expect(response.stack_name).to(eq(@hello_world_create_response['stack_name']))
        expect(response.message).to(be_nil)
        expect(response.details).to(be_nil)
      end

      it "handles trailing '/' in template path" do
        async_response = Terraform::Runner.run_async(input_vars, File.join(__dir__, "runner/data/hello-world/"))
        expect(create_stub).to(have_been_requested.times(1))

        response = async_response.response
        expect(retrieve_stub).to(have_been_requested.times(1))

        expect(response.status).to(eq('IN_PROGRESS'), "terraform-runner failed with:\n#{response.status}")
        expect(response.stack_id).to(eq(@hello_world_create_response['stack_id']))
        expect(response.action).to(eq('CREATE'))
        expect(response.stack_name).to(eq(@hello_world_create_response['stack_name']))
        expect(response.message).to(be_nil)
        expect(response.details).to(be_nil)
      end

      it "is aliased as run" do
        expect(Terraform::Runner.method(:run)).to(eq(Terraform::Runner.method(:run_async)))
      end
    end

    describe 'ResponseAsync' do
      retrieve_stub = nil

      before do
        ENV["TERRAFORM_RUNNER_URL"] = "https://1.2.3.4:7000"

        retrieve_stub = stub_request(:post, "https://1.2.3.4:7000/api/stack/retrieve")
                        .with(:body => hash_including({:stack_id => @hello_world_retrieve_response['stack_id']}))
                        .to_return(
                          :status => 200,
                          :body   => @hello_world_retrieve_response.to_json
                        )
      end

      it "retrieve hello-world completed result" do
        async_response = Terraform::Runner::ResponseAsync.new(@hello_world_create_response['stack_id'])
        response = async_response.response

        expect(response.status).to(eq('SUCCESS'), "terraform-runner failed with:\n#{response.status}")
        expect(response.message).to(include('greeting = "Hello World"'))
        expect(response.stack_id).to(eq(@hello_world_retrieve_response['stack_id']))
        expect(response.action).to(eq('CREATE'))
        expect(response.stack_name).to(eq(@hello_world_retrieve_response['stack_name']))
        expect(response.details.keys).to(eq(%w[resources outputs]))

        expect(retrieve_stub).to(have_been_requested.times(1))
      end
    end

    describe 'Stop running .run_async template job' do
      create_stub = nil
      retrieve_stub = nil
      cancel_stub = nil

      before do
        ENV["TERRAFORM_RUNNER_URL"] = "https://1.2.3.4:7000"

        create_stub = stub_request(:post, "https://1.2.3.4:7000/api/stack/create")
                      .with(:body => hash_including({:parameters => [], :cloud_providers => []}))
                      .to_return(
                        :status => 200,
                        :body   => @hello_world_create_response.to_json
                      )

        cancel_response = @hello_world_create_response.clone
        cancel_response[:status] = 'CANCELLED'

        retrieve_stub = stub_request(:post, "https://1.2.3.4:7000/api/stack/retrieve")
                        .with(:body => hash_including({:stack_id => @hello_world_retrieve_response['stack_id']}))
                        .to_return(
                          :status => 200,
                          :body   => @hello_world_create_response.to_json
                        )
                        .times(2)
                        .then
                        .to_return(
                          :status => 200,
                          :body   => cancel_response.to_json
                        )
        cancel_stub = stub_request(:post, "https://1.2.3.4:7000/api/stack/cancel")
                      .with(:body => hash_including({:stack_id => @hello_world_retrieve_response['stack_id']}))
                      .to_return(
                        :status => 200,
                        :body   => cancel_response.to_json
                      )
      end

      let(:input_vars) { {} }

      it "start running, then stop the before it completes" do
        async_response = Terraform::Runner.run_async(input_vars, File.join(__dir__, "runner/data/hello-world"))
        expect(create_stub).to(have_been_requested.times(1))
        expect(retrieve_stub).to(have_been_requested.times(0))

        response = async_response.response
        expect(retrieve_stub).to(have_been_requested.times(1))

        expect(response.status).to(eq('IN_PROGRESS'), "terraform-runner failed with:\n#{response.status}")
        expect(response.stack_id).to(eq(@hello_world_create_response['stack_id']))
        expect(response.action).to(eq('CREATE'))
        expect(response.stack_name).to(eq(@hello_world_create_response['stack_name']))
        expect(response.message).to(be_nil)
        expect(response.details).to(be_nil)

        # Stop the job terraform-runneer
        async_response.stop
        expect(cancel_stub).to(have_been_requested.times(1))
        expect(retrieve_stub).to(have_been_requested.times(2))

        # fetch latest response
        response = async_response.response
        expect(retrieve_stub).to(have_been_requested.times(3))
        expect(response.status).to(eq('CANCELLED'), "terraform-runner failed with:\n#{response.status}")

        # fetch latest response again, no more api calls
        response = async_response.response
        expect(retrieve_stub).to(have_been_requested.times(3))
        expect(response.status).to(eq('CANCELLED'), "terraform-runner failed with:\n#{response.status}")
      end
    end
  end

  context '.run with cloud credentials' do
    describe '.run_async with amazon credential' do
      let(:amazon_cred) do
        params = {
          :userid         => "manageiq-aws",
          :password       => "aws_secret",
          :security_token => "key_data",
        }
        credential_class = embedded_terraform::AmazonCredential
        credential_class.create_in_provider(manager.id, params)
      end

      let(:cloud_providers_conn_params) do
        [
          {
            'connection_parameters' => [
              {
                'name'    => 'AWS_ACCESS_KEY_ID',
                'value'   => 'manageiq-aws',
                'secured' => 'false',
              },
              {
                'name'    => 'AWS_SECRET_ACCESS_KEY',
                'value'   => 'aws_secret',
                'secured' => 'false',
              },
              {
                'name'    => 'AWS_SESSION_TOKEN',
                'value'   => 'key_data',
                'secured' => 'false',
              },
            ]
          }
        ]
      end

      # .with(:body => hash_including({:parameters => [], :cloud_providers => cloud_providers_conn_params}))

      def verify_req(req)
        body = JSON.parse(req.body)
        expect(body["parameters"]).to(eq([]))
        expect(body["cloud_providers"]).to(eq(cloud_providers_conn_params))
      end

      create_stub = nil

      before do
        ENV["TERRAFORM_RUNNER_URL"] = "https://1.2.3.4:7000"

        create_stub =
          stub_request(:post, "https://1.2.3.4:7000/api/stack/create")
          .with { |req| verify_req(req) }
          .to_return(
            :status => 200,
            :body   => @hello_world_create_response.to_json
          )
      end

      let(:input_vars) { {} }

      it "start running terraform template with amazon credential" do
        Terraform::Runner.run_async(
          input_vars,
          File.join(__dir__, "runner/data/hello-world"),
          :credentials => [amazon_cred]
        )
        expect(create_stub).to(have_been_requested.times(1))
      end
    end

    describe '.run_async with vSphere & ibmcloud credential' do
      let(:vsphere_cred) do
        params = {
          :userid   => "userid",
          :password => "secret1",
          :host     => "host"
        }
        credential_class = embedded_terraform::VsphereCredential
        credential_class.create_in_provider(manager.id, params)
      end

      let(:ibmcloud_cred) do
        params = {
          :auth_key => "ibmcloud-api-key",
        }
        credential_class = embedded_terraform::IbmCloudCredential
        credential_class.create_in_provider(manager.id, params)
      end

      let(:cloud_providers_conn_params) do
        [
          {
            "connection_parameters" => [
              {
                "name"    => 'VSPHERE_USER',
                "value"   => 'userid',
                "secured" => 'false',
              },
              {
                "name"    => 'VSPHERE_PASSWORD',
                "value"   => 'secret1',
                "secured" => 'false',
              },
              {
                "name"    => 'VSPHERE_SERVER',
                "value"   => 'host',
                "secured" => 'false',
              },
            ]
          },
          {
            "connection_parameters" => [
              {
                "name"    => 'IC_API_KEY',
                "value"   => 'ibmcloud-api-key',
                "secured" => 'false',
              },
            ]
          },
        ]
      end

      def verify_req(req)
        body = JSON.parse(req.body)
        expect(body["parameters"]).to(eq([]))
        expect(body["cloud_providers"]).to(eq(cloud_providers_conn_params))
      end

      create_stub = nil

      before do
        ENV["TERRAFORM_RUNNER_URL"] = "https://1.2.3.4:7000"

        create_stub =
          stub_request(:post, "https://1.2.3.4:7000/api/stack/create")
          .with { |req| verify_req(req) }
          .to_return(
            :status => 200,
            :body   => @hello_world_create_response.to_json
          )
      end

      let(:input_vars) { {} }

      it "start running terraform template with vSphere & ibmcloud credentials" do
        Terraform::Runner.run_async(
          input_vars,
          File.join(__dir__, "runner/data/hello-world"),
          :credentials => [vsphere_cred, ibmcloud_cred]
        )
        expect(create_stub).to(have_been_requested.times(1))
      end
    end
  end
end

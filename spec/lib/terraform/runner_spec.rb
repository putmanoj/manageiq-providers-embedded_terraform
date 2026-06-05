require 'webmock/rspec'
require 'json'

RSpec.describe(Terraform::Runner) do
  let(:terraform_runner_url) { "https://1.2.3.4:7000" }

  let(:embedded_terraform) { ManageIQ::Providers::EmbeddedTerraform::AutomationManager }
  let(:manager) { FactoryBot.create(:embedded_automation_manager_terraform) }

  before do
    stub_const("ENV", ENV.to_h.merge("TERRAFORM_RUNNER_URL" => terraform_runner_url))

    @hello_world_create_response = JSON.parse(File.read(File.join(__dir__, "runner/data/responses/hello-world-create-in-progress.json")))
    @hello_world_retrieve_create_response = JSON.parse(File.read(File.join(__dir__, "runner/data/responses/hello-world-retrieve-create-success.json")))
    @hello_world_update_response = JSON.parse(File.read(File.join(__dir__, "runner/data/responses/hello-world-update-in-progress.json")))
    @hello_world_retrieve_update_response = JSON.parse(File.read(File.join(__dir__, "runner/data/responses/hello-world-update-success.json")))
    @hello_world_delete_response = JSON.parse(File.read(File.join(__dir__, "runner/data/responses/hello-world-delete-in-progress.json")))
    @hello_world_retrieve_delete_response = JSON.parse(File.read(File.join(__dir__, "runner/data/responses/hello-world-delete-success.json")))
  end

  before do
    EmbeddedTerraformEvmSpecHelper.assign_embedded_terraform_role
  end

  describe "is .available" do
    before do
      stub_request(:get, "#{terraform_runner_url}/ready")
        .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
    end

    it "check if terraform-runner service is available" do
      expect(Terraform::Runner.available?).to(be(true))
    end
  end

  describe ".wait_for_runner_availability!" do
    let(:wait_time) { 10 }
    let(:check_interval) { 1 }

    before do
      stub_const("ENV", ENV.to_h.merge(
                          "TERRAFORM_RUNNER_URL"                         => terraform_runner_url,
                          "TERRAFORM_RUNNER_AVAILABILITY_WAIT_TIME"      => wait_time.to_s,
                          "TERRAFORM_RUNNER_AVAILABILITY_CHECK_INTERVAL" => check_interval.to_s
                        ))
      # Reset the @available instance variable before each test
      Terraform::Runner.instance_variable_set(:@available, nil)
    end

    context "when runner is immediately available" do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      it "does not wait and proceeds immediately" do
        expect(Terraform::Runner).not_to receive(:sleep)
        Terraform::Runner.send(:wait_for_runner_availability!)
      end
    end

    context "when runner becomes available after waiting" do
      before do
        # First 2 calls return unavailable, 3rd call returns available
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 503, :body => {:status => "DOWN"}.to_json)
          .times(2)
          .then
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      it "waits and succeeds when runner becomes available" do
        expect(Terraform::Runner).to receive(:sleep).with(check_interval).twice
        expect { Terraform::Runner.send(:wait_for_runner_availability!) }.not_to raise_error
      end
    end

    context "when runner never becomes available" do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 503, :body => {:status => "DOWN"}.to_json)
      end

      it "raises an error after timeout" do
        expect(Terraform::Runner).to receive(:sleep).with(check_interval).at_least(:once)
        expect { Terraform::Runner.send(:wait_for_runner_availability!) }
          .to raise_error(RuntimeError, /Terraform runner is not available after waiting/)
      end
    end

    context "when runner has connection errors" do
      before do
        # First 2 calls raise errors, 3rd call succeeds
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_raise(Faraday::ConnectionFailed)
          .times(2)
          .then
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      it "retries and succeeds when connection is restored" do
        expect(Terraform::Runner).to receive(:sleep).with(check_interval).twice
        expect { Terraform::Runner.send(:wait_for_runner_availability!) }.not_to raise_error
      end
    end
  end

  describe ".run_terraform_runner_stack_api with availability check" do
    let(:wait_time) { 10 }
    let(:check_interval) { 1 }

    before do
      stub_const("ENV", ENV.to_h.merge(
                          "TERRAFORM_RUNNER_URL"                         => terraform_runner_url,
                          "TERRAFORM_RUNNER_AVAILABILITY_WAIT_TIME"      => wait_time.to_s,
                          "TERRAFORM_RUNNER_AVAILABILITY_CHECK_INTERVAL" => check_interval.to_s
                        ))
      # Reset the @available instance variable before each test
      Terraform::Runner.instance_variable_set(:@available, nil)
    end

    context "when runner is available" do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      let!(:create_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/create")
          .to_return(:status => 200, :body => @hello_world_create_response.to_json)
      end

      it "proceeds with the API call without waiting" do
        expect(Terraform::Runner).not_to receive(:sleep)

        Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world"),
          {}
        )

        expect(create_stub).to have_been_requested.times(1)
      end
    end

    context "when runner becomes available after waiting" do
      before do
        # Reset @available to ensure fresh state
        Terraform::Runner.instance_variable_set(:@available, nil)

        # First call returns unavailable, second call returns available
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 503, :body => {:status => "DOWN"}.to_json)
          .times(1)
          .then
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      let!(:create_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/create")
          .to_return(:status => 200, :body => @hello_world_create_response.to_json)
      end

      it "waits for availability then proceeds with the API call" do
        expect(Terraform::Runner).to receive(:sleep).with(check_interval).once

        Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world"),
          {}
        )

        expect(create_stub).to have_been_requested.times(1)
      end
    end

    context "when runner never becomes available" do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 503, :body => {:status => "DOWN"}.to_json)
      end

      it "raises an error and does not make the API call" do
        create_stub = stub_request(:post, "#{terraform_runner_url}/api/stack/create")

        expect do
          Terraform::Runner.run(
            Terraform::Runner::ActionType::CREATE,
            File.join(__dir__, "runner/data/hello-world"),
            {}
          )
        end.to raise_error(RuntimeError, /Terraform runner is not available after waiting/)

        expect(create_stub).not_to have_been_requested
      end
    end
  end

  describe ".run_terraform_runner_stack_api with 503 error handling" do
    let(:wait_time) { 10 }
    let(:check_interval) { 1 }

    before do
      stub_const("ENV", ENV.to_h.merge(
                          "TERRAFORM_RUNNER_URL"                         => terraform_runner_url,
                          "TERRAFORM_RUNNER_AVAILABILITY_WAIT_TIME"      => wait_time.to_s,
                          "TERRAFORM_RUNNER_AVAILABILITY_CHECK_INTERVAL" => check_interval.to_s
                        ))
      # Reset the @available instance variable before each test
      Terraform::Runner.instance_variable_set(:@available, nil)
    end

    context "when API returns 503 error then succeeds on retry" do
      before do
        # Runner is initially available
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
          .times(1)
          .then
          # After 503, runner becomes unavailable then available again
          .to_return(:status => 503, :body => {:status => "DOWN"}.to_json)
          .times(1)
          .then
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      let!(:create_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/create")
          .to_return(:status => 503, :body => {
            :error => {
              :statusCode => 503,
              :name       => "ServiceUnavailable",
              :message    => "API is temporarily unavailable due to an active database migration."
            }
          }.to_json)
          .times(1)
          .then
          .to_return(:status => 200, :body => @hello_world_create_response.to_json)
      end

      it "waits for availability and retries the request" do
        expect(Terraform::Runner).to receive(:sleep).with(check_interval).once

        Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world"),
          {}
        )

        expect(create_stub).to have_been_requested.times(2)
      end
    end
  end

  describe ".run_terraform_runner_stack_api with connection error handling" do
    let(:wait_time) { 10 }
    let(:check_interval) { 1 }

    before do
      stub_const("ENV", ENV.to_h.merge(
                          "TERRAFORM_RUNNER_URL"                         => terraform_runner_url,
                          "TERRAFORM_RUNNER_AVAILABILITY_WAIT_TIME"      => wait_time.to_s,
                          "TERRAFORM_RUNNER_AVAILABILITY_CHECK_INTERVAL" => check_interval.to_s
                        ))
      # Reset the @available instance variable before each test
      Terraform::Runner.instance_variable_set(:@available, nil)
    end

    context "when API raises ConnectionFailed then succeeds on retry" do
      before do
        # Runner is initially available
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
          .times(1)
          .then
          # After connection failure, runner becomes unavailable then available again
          .to_return(:status => 503, :body => {:status => "DOWN"}.to_json)
          .times(1)
          .then
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      let!(:create_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/create")
          .to_raise(Faraday::ConnectionFailed.new("Connection refused"))
          .times(1)
          .then
          .to_return(:status => 200, :body => @hello_world_create_response.to_json)
      end

      it "waits for availability and retries the request" do
        expect(Terraform::Runner).to receive(:sleep).with(check_interval).once

        Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world"),
          {}
        )

        expect(create_stub).to have_been_requested.times(2)
      end
    end

    context "when API raises TimeoutError then succeeds on retry" do
      before do
        # Runner is initially available
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
          .times(1)
          .then
          # After timeout, runner becomes unavailable then available again
          .to_return(:status => 503, :body => {:status => "DOWN"}.to_json)
          .times(1)
          .then
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      let!(:create_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/create")
          .to_raise(Faraday::TimeoutError.new("Request timeout"))
          .times(1)
          .then
          .to_return(:status => 200, :body => @hello_world_create_response.to_json)
      end

      it "waits for availability and retries the request" do
        expect(Terraform::Runner).to receive(:sleep).with(check_interval).once

        Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world"),
          {}
        )

        expect(create_stub).to have_been_requested.times(2)
      end
    end
  end

  context 'Create Stack for hello-world terraform template' do
    describe '.run create stack with input_vars' do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      def verify_req(req)
        body = JSON.parse(req.body)
        expect(body["name"]).to(start_with('stack-'))
        expect(body).to(have_key('templateZipFile'))
        expect(body["parameters"]).to(eq([{"name" => "name", "value" => "New-World", "secured" => "false"}]))
        expect(body["cloud_providers"]).to(eq([]))
      end

      let!(:create_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/create")
          .with { |req| verify_req(req) }
          .to_return(
            :status => 200,
            :body   => @hello_world_create_response.to_json
          )
      end

      let!(:retrieve_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/retrieve")
          .with(:body => hash_including({:stack_id => @hello_world_retrieve_create_response['stack_id']}))
          .to_return(
            :status => 200,
            :body   => @hello_world_create_response.to_json
          )
      end

      let(:input_vars) { {'name' => 'New-World'} }

      let(:input_vars_type_constraints) do
        {
          "name" => {"name" => "name", "label" => "Name", "type" => "string", "description" => "name is required", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => "World"},
        }
      end

      it "start running hello-world terraform template" do
        async_response = Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world"),
          {
            :input_vars                  => input_vars,
            :input_vars_type_constraints => input_vars_type_constraints
          }
        )
        expect(create_stub).to(have_been_requested.times(1))

        response = async_response.response
        expect(retrieve_stub).to(have_been_requested.times(1))

        expect(response.status).to eq('IN_PROGRESS')
        expect(response.stack_id).to eq(@hello_world_create_response['stack_id'])
        expect(response.stack_job_id).to eq(@hello_world_create_response['stack_job_id'])
        expect(response.action).to eq('CREATE')
        expect(response.stack_name).to eq(@hello_world_create_response['stack_name'])
        expect(response.message).to be_nil
        expect(response.details).to be_nil
      end

      it "handles trailing '/' in template path" do
        async_response = Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world/"),
          {
            :input_vars                  => input_vars,
            :input_vars_type_constraints => input_vars_type_constraints
          }
        )
        expect(create_stub).to(have_been_requested.times(1))

        response = async_response.response
        expect(retrieve_stub).to(have_been_requested.times(1))

        expect(response.status).to eq('IN_PROGRESS')
        expect(response.stack_id).to eq(@hello_world_create_response['stack_id'])
        expect(response.stack_job_id).to eq(@hello_world_create_response['stack_job_id'])
        expect(response.action).to eq('CREATE')
        expect(response.stack_name).to eq(@hello_world_create_response['stack_name'])
        expect(response.message).to be_nil
        expect(response.details).to be_nil
      end
    end

    describe 'ResponseAsync' do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      let!(:retrieve_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/retrieve")
          .with(
            :body => hash_including({
                                      :stack_id => @hello_world_retrieve_create_response['stack_id']
                                    })
          )
          .to_return(
            :status => 200,
            :body   => @hello_world_retrieve_create_response.to_json
          )
      end

      let!(:retrieve_update_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/retrieve")
          .with(
            :body => hash_including({
                                      :stack_id     => @hello_world_retrieve_update_response['stack_id'],
                                      :stack_job_id => @hello_world_retrieve_update_response['stack_job_id']
                                    })
          )
          .to_return(
            :status => 200,
            :body   => @hello_world_retrieve_update_response.to_json
          )
      end

      it "retrieve hello-world completed result with only stack_id" do
        async_response = Terraform::Runner::ResponseAsync.new(
          @hello_world_create_response['stack_id']
        )

        expect(async_response.running?).to be false
        response = async_response.response

        expect(response.complete?).to be true
        expect(response.success?).to be true
        expect(response.message).to include('greeting = "Hello World"')
        expect(response.stack_id).to eq(@hello_world_retrieve_create_response['stack_id'])
        expect(response.stack_job_id).to eq(@hello_world_retrieve_create_response['stack_job_id'])
        expect(response.action).to eq('CREATE')
        expect(response.stack_name).to eq(@hello_world_retrieve_create_response['stack_name'])
        expect(response.details.keys).to eq(%w[resources outputs])

        expect(retrieve_stub).to have_been_requested.times(1)
      end

      it "retrieve hello-world completed result with stack_id & stack_job_id" do
        async_response = Terraform::Runner::ResponseAsync.new(
          @hello_world_update_response['stack_id'],
          @hello_world_update_response['stack_job_id']
        )

        expect(async_response.running?).to be false
        response = async_response.response

        expect(response.stack_id).to eq(@hello_world_update_response['stack_id'])
        expect(response.stack_job_id).to eq(@hello_world_update_response['stack_job_id'])
        expect(response.action).to eq('APPLY')
        expect(response.stack_name).to eq(@hello_world_update_response['stack_name'])

        expect(response.complete?).to be true
        expect(response.success?).to be true
        expect(response.message).to include('Apply complete! Resources: 1 added, 0 changed, 1 destroyed.')

        expect(retrieve_update_stub).to(have_been_requested.times(1))
      end
    end

    describe 'Stop running a create-stack job' do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      let!(:create_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/create")
          .with(:body => hash_including({:parameters => [], :cloud_providers => []}))
          .to_return(
            :status => 200,
            :body   => @hello_world_create_response.to_json
          )
      end

      let!(:cancel_response) { @hello_world_create_response.clone.merge(:status => 'CANCELLED') }

      let!(:retrieve_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/retrieve")
          .with(:body => hash_including({:stack_id => @hello_world_retrieve_create_response['stack_id']}))
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
      end

      let!(:cancel_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/cancel")
          .with(:body => hash_including({:stack_id => @hello_world_retrieve_create_response['stack_id']}))
          .to_return(
            :status => 200,
            :body   => cancel_response.to_json
          )
      end

      let(:input_vars) { {} }

      it ".run create stack job, then stop the job, before it completes" do
        async_response = Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world"),
          {
            :input_vars => input_vars
          }
        )
        expect(create_stub).to have_been_requested.times(1)
        expect(retrieve_stub).to have_been_requested.times(0)

        response = async_response.response
        expect(retrieve_stub).to have_been_requested.times(1)

        expect(response.status).to eq('IN_PROGRESS')
        expect(response.stack_id).to eq(@hello_world_create_response['stack_id'])
        expect(response.stack_job_id).to eq(@hello_world_create_response['stack_job_id'])
        expect(response.action).to eq('CREATE')
        expect(response.stack_name).to eq(@hello_world_create_response['stack_name'])
        expect(response.message).to be_nil
        expect(response.details).to be_nil

        # Stop the job terraform-runneer
        async_response.stop
        expect(cancel_stub).to have_been_requested.times(1)
        expect(retrieve_stub).to have_been_requested.times(2)

        # fetch latest response
        response = async_response.response
        expect(retrieve_stub).to have_been_requested.times(3)
        expect(response.status).to eq('CANCELLED')

        # fetch latest response again, no more api calls
        response = async_response.response
        expect(retrieve_stub).to have_been_requested.times(3)
        expect(response.status).to eq('CANCELLED')
      end

      it "is aliased as stop_stack" do
        expect(Terraform::Runner.method(:stop)).to eq(Terraform::Runner.method(:stop_async))
      end
    end

    describe 'Update stack for Reconfiguration of created stack' do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      def verify_req(req)
        body = JSON.parse(req.body)
        expect(body["stack_id"]).to eq(@hello_world_retrieve_update_response['stack_id'])
        expect(body).to have_key('templateZipFile')
        expect(body["parameters"]).to eq([{"name" => "name", "value" => "Future-World", "secured" => "false"}])
        expect(body["cloud_providers"]).to be_empty
      end

      let!(:update_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/apply")
          .with { |req| verify_req(req) }
          .to_return(
            :status => 200,
            :body   => @hello_world_update_response.to_json
          )
      end

      let!(:retrieve_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/retrieve")
          .with(:body => hash_including({:stack_id => @hello_world_retrieve_update_response['stack_id']}))
          .to_return(
            :status => 200,
            :body   => @hello_world_retrieve_update_response.to_json
          )
      end

      let(:input_vars) { {'name' => 'Future-World'} }

      let(:input_vars_type_constraints) do
        {
          "name" => {"name" => "name", "label" => "Name", "type" => "string", "description" => "name is required", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => "World"},
        }
      end

      it ".run update stack for reconfiguration of stack created with hello-world terraform template" do
        async_response = Terraform::Runner.run(
          Terraform::Runner::ActionType::UPDATE,
          File.join(__dir__, "runner/data/hello-world"),
          {
            :input_vars                  => input_vars,
            :input_vars_type_constraints => input_vars_type_constraints,
            :stack_id                    => @hello_world_retrieve_update_response['stack_id']
          }
        )
        expect(update_stub).to(have_been_requested.times(1))

        response = async_response.response
        expect(retrieve_stub).to have_been_requested.times(1)
        expect(response.stack_id).to eq(@hello_world_update_response['stack_id'])
        expect(response.stack_job_id).to eq(@hello_world_update_response['stack_job_id'])
        expect(response.action).to eq('APPLY')
        expect(response.stack_name).to eq(@hello_world_update_response['stack_name'])

        expect(response.status).to eq('SUCCESS')
        expect(response.message).to include('Apply complete! Resources: 1 added, 0 changed, 1 destroyed.')
      end
    end

    describe 'Delete stack for Retirement of created stack' do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

      def verify_req(req)
        body = JSON.parse(req.body)
        expect(body["stack_id"]).to(eq(@hello_world_retrieve_delete_response['stack_id']))
        expect(body).to(have_key('templateZipFile'))
        expect(body["parameters"]).to(eq([{"name" => "name", "value" => "Future-World", "secured" => "false"}]))
        expect(body["cloud_providers"]).to(eq([]))
      end

      let!(:delete_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/delete")
          .with { |req| verify_req(req) }
          .to_return(
            :status => 200,
            :body   => @hello_world_delete_response.to_json
          )
      end

      let!(:delete_retrieve_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/retrieve")
          .with(:body => hash_including({:stack_id => @hello_world_retrieve_delete_response['stack_id']}))
          .to_return(
            :status => 200,
            :body   => @hello_world_retrieve_delete_response.to_json
          )
      end

      let(:input_vars) { {'name' => 'Future-World'} }

      let(:input_vars_type_constraints) do
        {
          "name" => {"name" => "name", "label" => "Name", "type" => "string", "description" => "name is required", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => "World"},
        }
      end

      it ".run delete stack for retirement of stack created with hello-world terraform template" do
        async_response = Terraform::Runner.run(
          Terraform::Runner::ActionType::DELETE,
          File.join(__dir__, "runner/data/hello-world"),
          {
            :input_vars                  => input_vars,
            :input_vars_type_constraints => input_vars_type_constraints,
            :stack_id                    => @hello_world_retrieve_delete_response['stack_id'],
          }
        )
        expect(delete_stub).to(have_been_requested.times(1))

        response = async_response.response
        expect(delete_retrieve_stub).to have_been_requested.times(1)
        expect(response.stack_id).to eq(@hello_world_delete_response['stack_id'])
        expect(response.stack_job_id).to eq(@hello_world_delete_response['stack_job_id'])
        expect(response.action).to eq('DELETE')
        expect(response.stack_name).to eq(@hello_world_delete_response['stack_name'])

        expect(response.status).to eq('SUCCESS')
        expect(response.message).to include('Destroy complete! Resources: 1 destroyed.')
        expect(response.details).to eq({"resources" => [], "outputs" => []})
      end
    end
  end

  context 'Create stack with cloud credentials' do
    describe 'Create stack with amazon credential' do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

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
        expect(body["parameters"]).to be_empty
        expect(body["cloud_providers"]).to eq(cloud_providers_conn_params)
      end

      let!(:create_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/create")
          .with { |req| verify_req(req) }
          .to_return(
            :status => 200,
            :body   => @hello_world_create_response.to_json
          )
      end

      let(:input_vars) { {} }

      it ".run create stack for terraform template with amazon credential" do
        Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world"),
          {
            :input_vars  => input_vars,
            :credentials => [amazon_cred]
          }
        )
        expect(create_stub).to have_been_requested.times(1)
      end
    end

    describe 'Create stack with vSphere & ibmcloud credential' do
      before do
        stub_request(:get, "#{terraform_runner_url}/ready")
          .to_return(:status => 200, :body => {:status => "UP", :checks => []}.to_json)
      end

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
        expect(body["parameters"]).to be_empty
        expect(body["cloud_providers"]).to eq(cloud_providers_conn_params)
      end

      let!(:create_stub) do
        stub_request(:post, "#{terraform_runner_url}/api/stack/create")
          .with { |req| verify_req(req) }
          .to_return(
            :status => 200,
            :body   => @hello_world_create_response.to_json
          )
      end

      let(:input_vars) { {} }

      it ".run create stack with terraform template with vSphere & ibmcloud credentials" do
        Terraform::Runner.run(
          Terraform::Runner::ActionType::CREATE,
          File.join(__dir__, "runner/data/hello-world"),
          {
            :input_vars  => input_vars,
            :credentials => [vsphere_cred, ibmcloud_cred]
          }
        )
        expect(create_stub).to have_been_requested.times(1)
      end
    end
  end

  context '.parse_template_variables hello-world' do
    describe '.parse_template_variables input/output vars' do
      def verify_req(req)
        body = JSON.parse(req.body)
        expect(body).to(have_key('templateZipFile'))
      end

      let!(:template_variables_stub) do
        hello_world_variables_response = JSON.parse(File.read(File.join(__dir__, "runner/data/responses/hello-world-variables-success.json")))
        stub_request(:post, "#{terraform_runner_url}/api/template/variables")
          .with { |req| verify_req(req) }
          .to_return(
            :status => 200,
            :body   => hello_world_variables_response.to_json
          )
      end

      it "parse input/output params from hello-world terraform template" do
        response = Terraform::Runner.parse_template_variables(File.join(__dir__, "runner/data/hello-world"))
        expect(template_variables_stub).to have_been_requested.times(1)

        template_input_params = response['template_input_params']
        expect(template_input_params.length).to eq(1)
        expect(template_input_params.first).to be_kind_of(Hash).and include(
          "name"        => "name",
          "label"       => "name",
          "type"        => "string",
          "description" => "",
          "required"    => true,
          "secured"     => false,
          "hidden"      => false,
          "immutable"   => false,
          "default"     => "World"
        )

        template_output_params = response['template_output_params']
        expect(template_output_params.length).to eq(1)
        expect(template_output_params.first).to be_kind_of(Hash).and include(
          "name"        => "greeting",
          "label"       => "greeting",
          "description" => "",
          "secured"     => false,
          "hidden"      => false
        )

        terraform_version = response['terraform_version']
        expect(terraform_version).to eq('>= 1.1.0')
      end
    end
  end
end

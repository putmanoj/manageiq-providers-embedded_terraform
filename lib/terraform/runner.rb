require 'faraday'
require 'tempfile'
require 'zip'
require 'base64'

module Terraform
  class Runner
    class << self
      def available?
        return @available if defined?(@available)

        response = terraform_runner_client.get('live')
        @available = response.status == 200 && JSON.parse(response.body)['status'] == 'UP'
      rescue
        @available = false
      end

      # Run a template, initiates terraform-runner job for running a template, via terraform-runner api
      #
      # @param input_vars [Hash] Hash with key/value pairs that will be passed as input variables to the
      #        terraform-runner run
      # @param template_path [String] Path to the template we will want to run
      # @param tags [Hash] Hash with key/values pairs that will be passed as tags to the terraform-runner run
      # @param credentials [Array] List of Authentication objects to provide to the terraform run
      # @param env_vars [Hash] Hash with key/value pairs that will be passed as environment variables to the
      #        terraform-runner run
      # @return [Terraform::Runner::ResponseAsync] Response object of terraform-runner create action
      def run_async(input_vars, template_path, tags: nil, credentials: [], env_vars: {})
        _log.debug("Run_aysnc template: #{template_path}")
        response = create_stack_job(
          template_path,
          :input_vars  => input_vars,
          :tags        => tags,
          :credentials => credentials,
          :env_vars    => env_vars
        )
        Terraform::Runner::ResponseAsync.new(response.stack_id)
      end

      # To simplify clients who may just call run, we alias it to call
      # run_async.  If we ever need run_sync, we'll need to revisit this.
      alias run run_async

      # Stop running terraform-runner job by stack_id
      #
      # @param stack_id [String] stack_id from the terraforn-runner job
      #
      # @return [Terraform::Runner::Response] Response object with result of terraform run
      def stop_async(stack_id)
        cancel_stack_job(stack_id)
      end

      # Fetch terraform-runner job result/status by stack_id
      #
      # @param stack_id [String] stack_id from the terraforn-runner job
      #
      # @return [Terraform::Runner::Response] Response object with result of terraform run
      def fetch_result_by_stack_id(stack_id)
        retrieve_stack_job(stack_id)
      end

      # =================================================
      # TerraformRunner Stack-API interaction methods
      # =================================================
      private

      def server_url
        ENV.fetch('TERRAFORM_RUNNER_URL', 'https://opentofu-runner:6000')
      end

      def server_token
        @server_token ||= ENV.fetch('TERRAFORM_RUNNER_TOKEN', jwt_token)
      end

      def stack_job_interval_in_secs
        ENV.fetch('TERRAFORM_RUNNER_STACK_JOB_CHECK_INTERVAL', 10).to_i
      end

      def stack_job_max_time_in_secs
        ENV.fetch('TERRAFORM_RUNNER_STACK_JOB_MAX_TIME', 120).to_i
      end

      # create http client for terraform-runner rest-api
      def terraform_runner_client
        @terraform_runner_client ||= begin
          # TODO: verify ssl
          verify_ssl = false

          Faraday.new(
            :url => server_url,
            :ssl => {:verify => verify_ssl}
          ) do |builder|
            builder.request(:authorization, 'Bearer', -> { server_token })
          end
        end
      end

      def stack_tenant_id
        '00000000-0000-0000-0000-000000000000'.freeze
      end

      def json_post_arguments(payload)
        return JSON.generate(payload), "Content-Type" => "application/json".freeze
      end

      def provider_connection_parameters(credentials)
        credentials.collect do |cred|
          {
            'connection_parameters' => Terraform::Runner::Credential.new(cred.id).connection_parameters
          }
        end
      end

      # Create TerraformRunner Stack Job
      def create_stack_job(
        template_path,
        input_vars: [],
        tags: nil,
        credentials: [],
        env_vars: {},
        name: "stack-#{rand(36**8).to_s(36)}"
      )
        _log.info("start stack_job for template: #{template_path}")
        tenant_id = stack_tenant_id
        encoded_zip_file = encoded_zip_from_directory(template_path)

        # TODO: use tags,env_vars
        payload = {
          :cloud_providers => provider_connection_parameters(credentials),
          :name            => name,
          :tenantId        => tenant_id,
          :templateZipFile => encoded_zip_file,
          :parameters      => ApiParams.to_cam_parameters(input_vars)
        }

        http_response = terraform_runner_client.post(
          "api/stack/create",
          *json_post_arguments(payload)
        )
        _log.debug("==== http_response.body: \n #{http_response.body}")
        _log.info("stack_job for template: #{template_path} running ...")
        Terraform::Runner::Response.parsed_response(http_response)
      end

      # Retrieve TerraformRunner Stack Job details
      def retrieve_stack_job(stack_id)
        http_response = terraform_runner_client.post(
          "api/stack/retrieve",
          *json_post_arguments({:stack_id => stack_id})
        )
        _log.info("==== Retrieve Stack Response: \n #{http_response.body}")
        Terraform::Runner::Response.parsed_response(http_response)
      end

      # Cancel/Stop running TerraformRunner Stack Job
      def cancel_stack_job(stack_id)
        http_response = terraform_runner_client.post(
          "api/stack/cancel",
          *json_post_arguments({:stack_id => stack_id})
        )
        _log.info("==== Cancel Stack Response: \n #{http_response.body}")
        Terraform::Runner::Response.parsed_response(http_response)
      end

      # encode zip of a template directory
      def encoded_zip_from_directory(template_path)
        dir_path = template_path # directory to be zipped
        dir_path = dir_path[0...-1] if dir_path.end_with?('/')

        Tempfile.create(%w[opentofu-runner-payload .zip]) do |zip_file_path|
          _log.debug("Create #{zip_file_path}")
          Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
            Dir.chdir(dir_path)
            Dir.glob("**/*").select { |fn| File.file?(fn) }.each do |file|
              _log.debug("Adding #{file}")
              zipfile.add(file.sub("#{dir_path}/", ''), file)
            end
          end
          Base64.encode64(File.binread(zip_file_path))
        end
      end

      def jwt_token
        require "jwt"

        payload = {'Username' => 'opentofu-runner'}
        JWT.encode(payload, v2_key.key, 'HS256')
      end

      def v2_key
        ManageIQ::Password.key
      end
    end
  end
end

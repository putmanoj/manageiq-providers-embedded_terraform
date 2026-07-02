require 'faraday'
require 'tempfile'
require 'zip'
require 'base64'

module Terraform
  class Runner
    class TemporarilyUnavailable < StandardError; end

    class << self
      def available?
        @available_mutex = Mutex.new unless defined?(@available_mutex)

        # If previously available, return cached true
        return true if defined?(@available) && @available == true

        # If previously unavailable and within availability-cache TTL, return cached false
        return false if availability_cache_live?

        @available_mutex.synchronize do
          # Double-check inside mutex (another thread may have updated)
          return false if availability_cache_live?

          # Fetch ready status from Terraform Runner service
          response = terraform_runner_client.get('ready')
          $embedded_terraform_log.debug("Terraform runner ready check response: #{response.body}")
          @available = response.status == 200 && JSON.parse(response.body)['status'] == 'UP'
          @available_checked_at = Time.now.utc unless @available
          @available
        rescue
          @available = false
          @available_checked_at = Time.now.utc
          false
        end
      end

      def reset_available!
        reset_availability_cache!
      end

      # Run TerraformRunner Stack actions with a Terraform template.
      #
      # @param action_type   [String] (required) a action to run, use one of Terraform::Runner::ActionType::<constant>
      # @param template_path [String] (required) path to the terraform template directory.
      # @param options       [Hash]   (optional) key/values pairs
      #
      # @return [Terraform::Runner::ResponseAsync] Response object of terraform-runner api call
      #
      # Note:
      # * supported in 'action_type' :
      #   1. ActionType::CREATE   (Provision)   create new stack - `terraform apply`.
      #   2. ActionType::UPDATE   (Reconfigure) update a existing stack - `terraform apply`.
      #   3. ActionType::DELETE   (Retirement)  destroy a existing stack/resources - `terraform destroy`.
      #   4. ActionType::RETRIEVE (Fetch)       fetch a existing stack object json from terraform-runner.
      #   5. ActionType::CANCEL   (Stop)        stop running stack job in terraform-runner.
      # * keys allowed in ':options'
      #   - :input_vars                  [Hash]   (optional) key/value pairs, as input variables for the terraform-runner run job.
      #   - :input_vars_type_constraints [Hash]   (optional) key/value(type constraints object, from Terraform Runner) pairs.
      #   - :tags                        [Hash]   (optional) key/value pairs tags for terraform-runner Provisioned resources.
      #   - :credentials                 [Array]  (optional) list of authentication objects for the terraform run job.
      #   - :env_vars                    [Hash]   (optional) key/value pairs, used as environment variables, for terraform-runner run job.
      #   - :name                        [String] (optional) name for new created stack in terraform-runner.
      #   - :stack_id                    [String] [required] if Reconfigure/Retire/Retrieve/Cancel actions.
      #
      def run(action_type, template_path, options = {})
        raise "Not supported action type in this method, instead use method parse_terraform_variables" if action_type == ActionType::TEMPLATE_VARIABLES
        raise "Not supported action type '#{action_type}'" unless ActionType.actions.include?(action_type)

        response = run_terraform_runner_stack_api(
          Request.new(
            action_type,
            options.merge(
              :template_path => template_path,
              :tenant_id     => stack_tenant_id
            )
          )
        )

        Terraform::Runner::ResponseAsync.new(response.stack_id, response.stack_job_id)
      end

      # Stop/Cancel running terraform-runner job, by stack_id
      #
      # @param stack_id     [String] (required) stack_id from the terraforn-runner job
      # @param stack_job_id [String] (optional) if not provided fetches latest job, else particular job of terraforn-runner stack object
      #
      # @return [Terraform::Runner::Response] Response object with result of terraform run
      def stop_async(stack_id, stack_job_id = nil)
        run_terraform_runner_stack_api(
          Request.new(
            ActionType::CANCEL,
            {
              :stack_id     => stack_id,
              :stack_job_id => stack_job_id,
              :tenant_id    => stack_tenant_id
            }
          )
        )
      end

      # To simplify clients who want to stop a running stack job, we alias it to call stop_async
      alias stop stop_async

      # Fetch/Retrieve stack object(with result/status), by stack_id from terraform-runner
      #
      # @param stack_id     [String] (required) stack_id of terraforn-runner stack object
      # @param stack_job_id [String] (optional) if not provided fetches latest job, else particular job of terraforn-runner stack object
      #
      # @return [Terraform::Runner::Response] Response object with result of terraform run
      def retrieve_stack(stack_id, stack_job_id = nil)
        $embedded_terraform_log.debug("Retrieve terraform runner stack: #{stack_id}/#{stack_job_id}")
        run_terraform_runner_stack_api(
          Request.new(
            ActionType::RETRIEVE,
            {
              :stack_id     => stack_id,
              :stack_job_id => stack_job_id,
              :tenant_id    => stack_tenant_id
            }
          )
        )
      end

      # To simplify clients who want to fetch stack object from terraform-runner
      alias stack retrieve_stack

      # Parse Terraform Template input/output variables
      #
      # @param template_path [String] Path to the template we will want to parse for input/output variables
      # @return Response(body) object of terraform-runner api/template/variables,
      #         - the response object had template_input_params, template_output_params and terraform_version
      def parse_template_variables(template_path)
        request = Request.new(ActionType::TEMPLATE_VARIABLES, {:template_path => template_path})
        action_endpoint = ActionType.action_endpoint(ActionType::TEMPLATE_VARIABLES)

        http_response = post(action_endpoint, request)

        $embedded_terraform_log.debug("==== http_response.body: \n #{http_response.body}")
        JSON.parse(http_response.body)
      end

      private

      def server_url
        ENV.fetch('TERRAFORM_RUNNER_URL', 'https://opentofu-runner:6000')
      end

      def server_token
        @server_token ||= ENV.fetch('TERRAFORM_RUNNER_TOKEN', jwt_token)
      end

      def availability_cache_ttl
        ENV.fetch('TERRAFORM_RUNNER_AVAILABILITY_CACHE_TTL', 30).to_i # in seconds
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

      def run_terraform_runner_stack_api(request)
        action_endpoint = ActionType.action_endpoint(request.action_type)

        http_response = post(action_endpoint, request)

        if request.action_type == ActionType::CREATE
          $embedded_terraform_log.info("terraform-runnner #{action_endpoint} for #{request.options["name"]} is running ...")
        else
          $embedded_terraform_log.info("terraform-runnner #{action_endpoint} for #{request.options["name"]}/#{request.options["stack_id"]}/#{request.options["stack_job_id"]} is running ...")
        end

        $embedded_terraform_log.debug("==== http_response.body: \n #{http_response.body}")

        Terraform::Runner::Response.parsed_response(http_response).tap do |resp|
          $embedded_terraform_log.info("terraform-runnner[#{action_endpoint}] stack/#{resp.stack_id}/#{resp.stack_job_id}")
        end
      end

      # Post to terraform-runner API — single attempt, fail fast.
      #
      # @param action_endpoint [String] The API endpoint to post to
      # @param request [Terraform::Runner::Request] The request object containing the payload
      # @return [Faraday::Response] The HTTP response from the API
      # @raise [Terraform::Runner::TemporarilyUnavailable] on 503 response or connection/timeout error
      def post(action_endpoint, request)
        http_response = terraform_runner_client.post(
          action_endpoint,
          *request.build_json_post_arguments
        )

        if http_response.status == 503
          reset_availability_cache!
          raise Terraform::Runner::TemporarilyUnavailable, "Terraform runner returned 503"
        end

        http_response
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        reset_availability_cache!
        raise Terraform::Runner::TemporarilyUnavailable, "Terraform runner not reachable: #{e.message}"
      end

      def availability_cache_live?
        defined?(@available) &&
          @available == false &&
          @available_checked_at &&
          ((Time.now.utc - @available_checked_at) < availability_cache_ttl)
      end

      def reset_availability_cache!
        @available_mutex = Mutex.new unless defined?(@available_mutex)
        @available_mutex.synchronize do
          @available = false
          @available_checked_at = nil
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

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

      # Provision or Create (terraform apply) a stack in terraform-runner for a terraform template.
      #
      # @param template_path [String] (required) path to the terraform template directory.
      # @param input_vars    [Hash]   (optional) key/value pairs as input variables for the terraform-runner run job.
      # @param input_vars_type_constraints
      #                      [Hash]   (optional) key/value(type constraints object, from Terraform Runner) pair.
      # @param tags          [Hash]   (optional) key/value pairs tags for terraform-runner Provisioned resources.
      # @param credentials   [Array]  (optional) List of Authentication objects for the terraform run job.
      # @param env_vars      [Hash]   (optional) key/value pairs used as environment variables, for terraform-runner run job.
      # @param nane          [String] (optional) name for the stack in terraform-runner.
      #
      # @return [Terraform::Runner::ResponseAsync] Response object of terraform-runner api call
      def create_stack(template_path, input_vars: {}, input_vars_type_constraints: [], tags: nil, credentials: [], env_vars: {},
                       name: "stack-#{rand(36**8).to_s(36)}")
        _log.debug("Run_aysnc/create_stack for template: #{template_path}")
        if template_path.present?
          response = run_terraform_runner_stack_api(
            Request.new(ActionType::CREATE)
              .template_path(template_path)
              .name(name)
              .credentials(credentials)
              .input_vars(input_vars, input_vars_type_constraints)
              .tenant_id(stack_tenant_id)
              .tags(tags)
              .env_vars(env_vars)
          )

          Terraform::Runner::ResponseAsync.new(response.stack_id)
        else
          raise "'template_path' is required for #{ResourceAction::Provision} action"
        end
      end

      # Reconfigure or Update(terraform apply) a existing stack in terraform-runner.
      #
      # @param stack_id      [String] (optional) required, if running ResourceAction::RECONFIGURE action, used by Terraform-Runner update job.
      # @param template_path [String] (required) path to the terraform template directory.
      # @param input_vars    [Hash]   (optional) key/value pairs as input variables for the terraform-runner run job.
      # @param input_vars_type_constraints
      #                      [Hash]   (optional) key/value(type constraints object, from Terraform Runner) pair.
      # @param credentials   [Array]  (optional) List of Authentication objects for the terraform run job.
      # @param env_vars      [Hash]   (optional) key/value pairs used as environment variables, for terraform-runner run job.
      #
      # @return [Terraform::Runner::ResponseAsync] Response object of terraform-runner api call
      def update_stack(stack_id, template_path, input_vars: {}, input_vars_type_constraints: [], credentials: [], env_vars: {})
        if stack_id.present? && template_path.present?
          _log.debug("Run_aysnc/update_stack('#{stack_id}') for template: #{template_path}")

          response = run_terraform_runner_stack_api(
            Request.new(ActionType::APPLY)
              .stack_id(stack_id)
              .template_path(template_path)
              .credentials(credentials)
              .input_vars(input_vars, input_vars_type_constraints)
              .tenant_id(stack_tenant_id)
              .env_vars(env_vars)
          )

          Terraform::Runner::ResponseAsync.new(response.stack_id)
        else
          _log.error("'stack_id' && 'template_path' are required for #{ResourceAction::RECONFIGURE} action")
          raise "'stack_id' && 'template_path' are required for #{ResourceAction::RECONFIGURE} action"
        end
      end

      # Retire or Delete(terraform destroy) the terraform-runner created stack resources.
      #
      # @param stack_id      [String] (optional) required, if running ResourceAction::RETIREMENT action, used by Terraform-Runner stack_delete job.
      # @param template_path [String] (required) path to the terraform template directory.
      # @param input_vars    [Hash]   (optional) key/value pairs as input variables for the terraform-runner run job.
      # @param input_vars_type_constraints
      #                      [Hash]   (optional) key/value(type constraints object, from Terraform Runner) pair.
      # @param credentials   [Array]  (optional) List of Authentication objects for the terraform run job.
      # @param env_vars      [Hash]   (optional) key/value pairs used as environment variables, for terraform-runner run job.
      #
      # @return [Terraform::Runner::ResponseAsync] Response object of terraform-runner api call
      def delete_stack(stack_id, template_path, input_vars: {}, input_vars_type_constraints: [], credentials: [], env_vars: {})
        if stack_id.present? && template_path.present?
          _log.debug("Run_aysnc/delete_stack('#{stack_id}') for template: #{template_path}")

          response = run_terraform_runner_stack_api(
            Request.new(ActionType::DELETE)
              .stack_id(stack_id)
              .template_path(template_path)
              .credentials(credentials)
              .input_vars(input_vars, input_vars_type_constraints)
              .tenant_id(stack_tenant_id)
              .env_vars(env_vars)
          )

          Terraform::Runner::ResponseAsync.new(response.stack_id)
        else
          _log.error("'stack_id' && 'template_path' are required for #{ResourceAction::RETIREMENT} action")
          raise "'stack_id' && 'template_path' are required for #{ResourceAction::RETIREMENT} action"
        end
      end

      # Stop/Cancel running terraform-runner job, by stack_id
      #
      # @param stack_id [String] stack_id from the terraforn-runner job
      #
      # @return [Terraform::Runner::Response] Response object with result of terraform run
      def stop_async(stack_id)
        run_terraform_runner_stack_api(
          Request.new(ActionType::CANCEL)
            .stack_id(stack_id)
        )
      end

      # To simplify clients who want to stop a running stack job, we alias it to call stop_async
      alias stop_stack stop_async

      # Fetch/Retrieve stack object(with result/status), by stack_id from terraform-runner
      #
      # @param stack_id [String] stack_id for the terraforn-runner stack job
      #
      # @return [Terraform::Runner::Response] Response object with result of terraform run
      def fetch_result_by_stack_id(stack_id)
        run_terraform_runner_stack_api(
          Request.new(ActionType::RETRIEVE)
            .stack_id(stack_id)
        )
      end

      # To simplify clients who want to fetch stack object from terraform-runner
      alias stack fetch_result_by_stack_id

      # Parse Terraform Template input/output variables
      # @param template_path [String] Path to the template we will want to parse for input/output variables
      # @return Response(body) object of terraform-runner api/template/variables,
      #         - the response object had template_input_params, template_output_params and terraform_version
      def parse_template_variables(template_path)
        request = Request.new(ActionType::TEMPLATE_VARIABLES).template_path(template_path)
        action_endpoint = ActionType.action_endpoint(ActionType::TEMPLATE_VARIABLES)

        http_response = terraform_runner_client.post(
          action_endpoint,
          *request.build_json_post_arguments
        )

        _log.debug("==== http_response.body: \n #{http_response.body}")
        JSON.parse(http_response.body)
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

      def run_terraform_runner_stack_api(request)
        action_endpoint = ActionType.action_endpoint(request.action_type)

        http_response = terraform_runner_client.post(
          action_endpoint,
          *request.build_json_post_arguments
        )
        _log.info("terraform-runnner[#{action_endpoint}] running ...")

        _log.debug("==== http_response.body: \n #{http_response.body}")
        Terraform::Runner::Response.parsed_response(http_response)
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

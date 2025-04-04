require 'json'

module Terraform
  class Runner
    class Response
      include Vmdb::Logging

      attr_reader :stack_id, :stack_name, :status, :action, :message, :error_message,
                  :details, :created_at, :stack_job_start_time, :stack_job_end_time,
                  :stack_job_id, :stack_job_is_latest

      # @return [String] Extracted attributes from the JSON response body object
      def self.parsed_response(http_response)
        data = JSON.parse(http_response.body)
        $embedded_terraform_log.debug("data : #{data}")
        Terraform::Runner::Response.new(data)
      end

      # Response object designed for holding full response from terraform-runner
      #
      # @param data  [Hash] key/values pairs
      #    keys supported in data :
      #      - stack_id             [String]  terraform-runner stack instance id
      #      - stack_job_id         [String]  terraform-runner stack job id for the action
      #      - stack_job_is_latest  [Boolean] is latest job, or previous job
      #      - stack_name           [String]  name of the stack instance
      #      - status               [String]  IN_PROGRESS/SUCCESS/FAILED
      #      - action               [String]  action performed CREATE,DESTROY,etc
      #      - message              [String]  Stdout from terraform-runner stack instance run
      #      - error_message        [String]  Stderr from terraform-runner run instance run
      #      - debug                [Boolean] whether or not to delete base_dir after run (for debugging)
      #      - details              [Hash]
      #      - created_at           [String]
      #      - stack_job_start_time [String]
      #      - stack_job_end_time   [String]
      #
      def initialize(data)
        @stack_id             = data['stack_id']
        @stack_job_id         = data['stack_job_id']
        @stack_job_is_latest  = data['stack_job_is_latest']
        @stack_name           = data['stack_name']
        @status               = data['status']
        @action               = data['action']
        @message              = data['message']
        @error_message        = data['error_message']
        @details              = data['details']
        @created_at           = data['created_at']
        @stack_job_start_time = data['stack_job_start_time']
        @stack_job_end_time   = data['stack_job_end_time']
      end
    end
  end
end

module Terraform
  class Runner
    class ResponseAsync
      include Vmdb::Logging

      attr_reader :stack_id, :stack_job_id

      # Response object designed for holding full response from terraform-runner stack job
      #
      # @param stack_id [String] terraform-runner stack job - stack_id
      def initialize(stack_id, stack_job_id = nil)
        @stack_id = stack_id
        @stack_job_id = stack_job_id
      end

      # @return [Boolean] true if the terraform stack job is still running, false when it's finished
      def running?
        return false if @response&.complete?

        # re-fetch response
        refresh_response

        !@response&.complete?
      end

      # Stops the running Terraform job
      def stop
        raise "No job running to stop" if !running?

        Terraform::Runner.stop(@stack_id, @stack_job_id)
      end

      # Re-Fetch async job's response
      def refresh_response
        @response = Terraform::Runner.retrieve_stack(@stack_id, @stack_job_id)

        @response
      end

      # # @return [Terraform::Runner::Response, NilClass] Response object with all details about the Terraform run, or nil
      # #         if the Terraform is still running
      # def response
      #   return if running?
      #
      #   @response
      # end

      # @return [Terraform::Runner::Response] Response object with all details about the Terraform run, or nil
      #         if the Terraform is still running
      def response
        if running?
          $embedded_terraform_log.debug("terraform-runner job [#{@stack_id}(#{@stack_job_id})] is running ...")
        end

        @response
      end
    end
  end
end

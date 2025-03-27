module Terraform
  class Runner
    class ResponseAsync
      include Vmdb::Logging

      attr_reader :stack_id

      # Response object designed for holding full response from terraform-runner stack job
      #
      # @param stack_id [String] terraform-runner stack job - stack_id
      def initialize(stack_id)
        @stack_id = stack_id
      end

      # @return [Boolean] true if the terraform stack job is still running, false when it's finished
      def running?
        return false if @response && completed?(@response.status)

        # re-fetch response
        refresh_response

        !completed?(@response.status)
      end

      # Stops the running Terraform job
      def stop
        raise "No job running to stop" if !running?

        Terraform::Runner.stop(@stack_id)
      end

      # Re-Fetch async job's response
      def refresh_response
        @response = Terraform::Runner.retrieve_stack_by_id(@stack_id)

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
          _log.info("terraform-runner job [#{@stack_id}] is still running ...")
        end

        @response
      end

      private

      def completed?(status)
        case status.to_s.upcase
        when "SUCCESS", "FAILED", "CANCELLED"
          true
        else
          false
        end
      end
    end
  end
end

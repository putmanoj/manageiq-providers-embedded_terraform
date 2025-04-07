module Terraform
  class Runner
    # TerraformRunner api/stack status
    class ResponseStackStatus
      IN_PROGRESS = 'IN_PROGRESS'.freeze
      SUCCESS = 'SUCCESS'.freeze
      SUCCESS_WITH_CHANGES = 'SUCCESS_WITH_CHANGES'.freeze
      FAILED = 'FAILED'.freeze
      FAILED_TIMED_OUT = 'FAILED_TIMED_OUT'.freeze
      CANCELLED = 'CANCELLED'.freeze

      def self.statuses
        [IN_PROGRESS, SUCCESS, SUCCESS_WITH_CHANGES, FAILED, FAILED_TIMED_OUT, CANCELLED].freeze
      end

      def self.success?(status)
        case status
        when SUCCESS, SUCCESS_WITH_CHANGES
          true
        else
          false
        end
      end

      def self.complete?(status)
        case status
        when SUCCESS, SUCCESS_WITH_CHANGES, FAILED, FAILED_TIMED_OUT, CANCELLED
          true
        else
          false
        end
      end
    end
  end
end

module Terraform
  class Runner
    # TerraformRunner api actions
    class ActionType
      CREATE = 'api/stack/create'.freeze
      APPLY = 'api/stack/apply'.freeze
      UPDATE = APPLY
      DELETE = 'api/stack/delete'.freeze
      CANCEL = 'api/stack/cancel'.freeze
      RETRIEVE = 'api/stack/retrieve'.freeze
      TEMPLATE_VARIABLES = 'api/template/variables'.freeze

      def self.action_endpoint(action_type)
        case action_type
        when ActionType::CREATE, ActionType::UPDATE, ActionType::DELETE,
          ActionType::CANCEL, ActionType::RETRIEVE, ActionType::TEMPLATE_VARIABLES
          action_type.to_s
        else
          raise "Invalid action type #{action_type}"
        end
      end
    end
  end
end

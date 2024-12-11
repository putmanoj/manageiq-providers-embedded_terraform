module Terraform
  class Runner
    class ApiParams
      # Add parameter in format required by terraform-runner api
      def self.add_param(param_list, param_value, param_name, is_secured: false)
        if param_list.nil?
          param_list = []
        end

        param_list.push(to_cam_param(param_name, param_value, :is_secured => is_secured))

        param_list
      end

      # add parameter, only if not blank or not nil,
      def self.add_param_if_present(param_list, param_value, param_name, is_secured: false)
        if param_value.present?
          param_list = add_param(param_list, param_value, param_name, :is_secured => is_secured)
        end

        param_list
      end

      # Convert to format required by terraform-runner api
      def self.to_cam_param(param_name, param_value, is_secured: false)
        {
          'name'    => param_name,
          'value'   => param_value,
          'secured' => is_secured ? 'true' : 'false',
        }
      end

      # Convert to paramaters as used by terraform-runner api
      #
      # @param vars [Hash] Hash with key/value pairs that will be passed as input variables to the
      #        terraform-runner run
      #
      # @return [Array] Array of {:name,:value}
      def self.to_cam_parameters(vars)
        return [] if vars.nil?

        vars.map do |key, value|
          to_cam_param(key, value)
        end
      end

      require 'set'
      TRUE_VALUES = ['T', 't', true, 'true', 'True', 'TRUE'].to_set

      # Normalize variables values, from ManageIQ values to Terraform Runner supported values
      # @param input_vars       [Hash] key/value pairs as input variables for the terraform-runner run job.
      # @param type_constraints [Hash] key/value(type constraints object, from Terraform Runner) pairs.
      #
      # @return [Array] Array of param objects [{name,value,secured}]
      def self.to_normalized_cam_parameters(input_vars, type_constraints)
        input_vars.map do |k, v|
          v, is_secured = normalized_param_value(k, v, type_constraints[k])

          to_cam_param(k, v, :is_secured => is_secured)
        end
      end

      def self.normalized_param_value(key, value, param_type_constraint)
        is_secured = false
        if param_type_constraint.present?
          param_secured, param_type, param_required = param_type_constraint.values_at('secured', 'type', 'required')

          is_secured = TRUE_VALUES.include?(param_secured)
          is_required = TRUE_VALUES.include?(param_required)

          case param_type
          when "boolean"
            value = TRUE_VALUES.include?(value)

          when "map"
            value = parse_json_value(key, value, :expected_type => Hash, :is_required => is_required)

          when "list"
            value = parse_json_value(key, value, :expected_type => Array, :is_required => is_required)

          else
            # string or number(string)
            # (number as string, is implicitly converted by terraform, so no conversion is requried here)
            if value.blank? && is_required == true
              raise "The variable '#{key}', cannot be empty"
            end
          end
        end

        [value, is_secured, param_type, is_required]
      end

      def self.parse_json_value(key, value, expected_type: Array, is_required: false)
        if value.kind_of?(String)
          if value.empty?
            value = nil
          else
            require 'json'
            begin
              value = JSON.parse(value)
            rescue JSON::ParserError
              raise "The variable '#{key}' does not have valid #{expected_type.name} value"
            end
          end
        end

        if value.nil?
          if is_required == true
            raise "The variable '#{key}' does not have valid #{expected_type.name} value"
          end
        elsif !value.kind_of?(expected_type)
          raise "The variable '#{key}' does not have valid #{expected_type.name} value"
        end

        value
      end
    end
  end
end

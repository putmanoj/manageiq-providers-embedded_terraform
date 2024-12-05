class Dialog
  class TerraformTemplateServiceDialog
    def self.create_dialog(label, terraform_template, extra_vars)
      new.create_dialog(label, terraform_template, extra_vars)
    end

    # This dialog is to be used by a terraform template service item
    def create_dialog(label, terraform_template, extra_vars)
      Dialog.new(:label => label, :buttons => "submit,cancel").tap do |dialog|
        tab = dialog.dialog_tabs.build(:display => "edit", :label => "Basic Information", :position => 0)
        position = 0
        if terraform_template.present? && add_template_variables_group(tab, position, terraform_template)
          position += 1
        end
        if extra_vars.present?
          add_variables_group(tab, position, extra_vars)
          position += 1
        end

        if position == 0
          # if not template input vars & no extra_vars,
          # then add single variable text box as place-holder
          add_variables_group(tab, position, {:name => {:default => label}})
        end

        dialog.save!
      end
    end

    JSONSTR_LIST_REGEX = '^\[[\W\w]*\]$'.freeze   # list of strings or objects
    JSONSTR_OBJECT_REGEX = '^\{[\W\w]*\}$'.freeze # map or object

    private

    def add_template_variables_group(tab, position, terraform_template)
      require "json"
      template_info = JSON.parse(terraform_template.payload)
      input_vars = template_info["input_vars"]

      return if input_vars.blank?

      tab.dialog_groups.build(
        :display  => "edit",
        :label    => "Terraform Template Variables",
        :position => position
      ).tap do |dialog_group|
        input_vars.each_with_index do |(var_info), index|
          key, value, required, readonly, hidden, label, description, type = var_info.values_at(
            "name", "default", "required", "immutable", "hidden", "label", "description", "type"
          )
          # TODO: use 'hidden' & 'secured' attributes, when adding variable field

          next if hidden

          case type
          when "boolean"
            add_check_box_field(
              key, value, dialog_group, index, label, description, readonly
            )
          when "map"
            add_json_variable_field(
              key, value, dialog_group, index, label, description, required, readonly, :is_list => false
            )
          when "list"
            add_json_variable_field(
              key, value, dialog_group, index, label, description, required, readonly, :is_list => true
            )
          else
            add_variable_field(
              key, value, dialog_group, index, label, description, required, readonly
            )
          end
        end
      end
    end

    def add_variables_group(tab, position, extra_vars)
      tab.dialog_groups.build(
        :display  => "edit",
        :label    => "Variables",
        :position => position
      ).tap do |dialog_group|
        extra_vars.transform_values { |val| val[:default] }.each_with_index do |(key, value), index|
          add_variable_field(key, value, dialog_group, index, key, key, false, false)
        end
      end
    end

    def add_variable_field(key, value, group, position, label, description, required, read_only)
      value = value.to_json if [Hash, Array].include?(value.class)
      description = key if description.blank?

      group.dialog_fields.build(
        :type           => "DialogFieldTextBox",
        :name           => key.to_s,
        :data_type      => "string",
        :display        => "edit",
        :required       => required,
        :default_value  => value,
        :label          => label,
        :description    => description,
        :reconfigurable => true,
        :position       => position,
        :dialog_group   => group,
        :read_only      => read_only
      )
    end

    def add_json_variable_field(key, value, group, position, label, description, required, read_only, is_list: false)
      value = JSON.pretty_generate(value) if [Hash, Array].include?(value.class)
      description = key if description.blank?

      group.dialog_fields.build(
        :type              => 'DialogFieldTextAreaBox',
        :name              => key.to_s,
        :data_type         => 'string',
        :display           => 'edit',
        :required          => required,
        :default_value     => value,
        :label             => label,
        :description       => description,
        :reconfigurable    => true,
        :position          => position,
        :dialog_group      => group,
        :read_only         => read_only,
        :validator_type    => 'regex',
        :validator_rule    => is_list ? JSONSTR_LIST_REGEX : JSONSTR_OBJECT_REGEX,
        :validator_message => "This field value must be a JSON #{is_list ? 'List' : 'Object or Map'}"
      )
    end

    def add_check_box_field(key, value, group, position, label, description, read_only)
      value = to_boolean(value)
      description = key if description.blank?

      group.dialog_fields.build(
        :type           => "DialogFieldCheckBox",
        :name           => key.to_s,
        :data_type      => "boolean",
        :default_value  => value,
        :label          => label,
        :description    => description,
        :reconfigurable => true,
        :position       => position,
        :dialog_group   => group,
        :read_only      => read_only
      )
    end

    def to_boolean(value)
      require 'active_model/type'
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end

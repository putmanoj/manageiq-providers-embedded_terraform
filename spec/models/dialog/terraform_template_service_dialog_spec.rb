RSpec.describe Dialog::TerraformTemplateServiceDialog do
  let(:payload_with_one_required_input_var) do
    '{"input_vars":[{"name":"name","label":"name","type":"string","description":"","required":true,"secured":false,"hidden":false,"immutable":false}]}'
  end
  let(:terraform_template_with_single_input_var) { FactoryBot.create(:terraform_template, :payload => payload_with_one_required_input_var) }

  let(:payload_with_three_input_vars) do
    '{"input_vars":[{"name":"create_wait","label":"create_wait","type":"string","description":"","required":true,"secured":false,"hidden":false,"immutable":false,"default":"30s"},{"name":"destroy_wait","label":"destroy_wait","type":"string","description":"","required":true,"secured":false,"hidden":false,"immutable":false,"default":"30s"},{"name":"name","label":"name","type":"string","description":"","required":true,"secured":false,"hidden":false,"immutable":false,"default":"World"}]}'
  end
  let(:terraform_template_with_input_vars) { FactoryBot.create(:terraform_template, :payload => payload_with_three_input_vars) }

  let(:terraform_template_with_no_input_vars) { FactoryBot.create(:terraform_template, :payload => '{"input_vars": []}') }

  describe "#create_dialog" do
    shared_examples_for "create_dialog with terraform template" do
      it "when has input vars" do
        dialog = described_class.create_dialog(dialog_label, terraform_template, {})
        expect(dialog).to have_attributes(:label => dialog_label, :buttons => "submit,cancel")

        group = assert_terraform_template_variables_tab(dialog)
        assert_terraform_variables_group(group, input_vars)
      end
    end

    context "template with single required input var (no default value)" do
      let(:dialog_label) { "myterraformdialog1" }
      let(:terraform_template) { terraform_template_with_single_input_var }
      let(:input_vars) do
        require 'json'
        payload = JSON.parse(payload_with_one_required_input_var)
        payload['input_vars']
      end

      it_behaves_like "create_dialog with terraform template"
    end

    context "template with muliple input vars with default values" do
      let(:dialog_label) { "myterraformdialog2" }
      let(:terraform_template) { terraform_template_with_input_vars }
      let(:input_vars) do
        require 'json'
        payload = JSON.parse(payload_with_three_input_vars)
        payload['input_vars']
      end

      it_behaves_like "create_dialog with terraform template"
    end

    context "with no terraform template input vars, but with extra vars" do
      let(:dialog_label) { 'mydialog1' }
      let(:extra_vars) do
        {
          'some_extra_var'  => {:default => 'blah'},
          'other_extra_var' => {:default => {'name' => 'some_value'}},
          'array_extra_var' => {:default => [{'name' => 'some_value'}]}
        }
      end
      let(:terraform_template) { terraform_template_with_no_input_vars }

      it "creates a dialog with extra variables" do
        dialog = subject.create_dialog(dialog_label, terraform_template, extra_vars)
        expect(dialog).to have_attributes(:label => dialog_label, :buttons => "submit,cancel")

        group = assert_variables_tab(dialog)
        assert_extra_variables_group(group)
      end
    end

    shared_examples_for "create_dialog with place-holder variable argument" do
      it "when no terraform template input vars and empty extra vars" do
        dialog = described_class.create_dialog(dialog_label, terraform_template, extra_vars)
        expect(dialog).to have_attributes(:label => dialog_label, :buttons => "submit,cancel")

        group = assert_variables_tab(dialog)
        assert_default_variables_group(group, dialog_label)
      end
    end

    context "when empty terraform template input vars & empty extra vars" do
      let(:dialog_label) { "mydialog2" }
      let(:terraform_template) { terraform_template_with_no_input_vars }
      let(:extra_vars) do
        {}
      end

      it_behaves_like "create_dialog with place-holder variable argument"
    end

    context "when nil terraform template & nil extra vars" do
      let(:dialog_label) { "mydialog3" }
      let(:terraform_template) { nil }
      let(:extra_vars) { nil }

      it_behaves_like "create_dialog with place-holder variable argument"
    end

    context "with terraform template input vars and with extra vars" do
      let(:dialog_label) { "mydialog4" }
      let(:extra_vars) do
        {
          'some_extra_var'  => {:default => 'blah'},
          'other_extra_var' => {:default => {'name' => 'some_value'}},
          'array_extra_var' => {:default => [{'name' => 'some_value'}]}
        }
      end
      let(:input_vars) do
        require 'json'
        payload = JSON.parse(payload_with_three_input_vars)
        payload['input_vars']
      end

      it "creates multiple dialog-groups" do
        dialog = subject.create_dialog(dialog_label, terraform_template_with_input_vars, extra_vars)
        expect(dialog).to have_attributes(:label => dialog_label, :buttons => "submit,cancel")

        group1 = assert_terraform_template_variables_tab(dialog, :group_size => 2)
        assert_terraform_variables_group(group1, input_vars)

        group2 = assert_variables_tab(dialog, :group_size => 2)
        assert_extra_variables_group(group2)
      end
    end

    context "with terraform boolean input variable" do
      let(:dialog_label) { "mydialog-with-boolean-field" }
      let(:input_vars) do
        [{"name" => "set_password", "label" => "set_password", "type" => "boolean", "description" => "Do you want to set the password ?", "required" => false, "secured" => false, "hidden" => false, "immutable" => false, "default" => true}]
      end
      let(:extra_vars) do
        {}
      end

      it "create_dialog with checkbox field, when default value is true" do
        terraform_template = FactoryBot.create(:terraform_template, :payload => "{\"input_vars\": #{input_vars.to_json}}")
        dialog = described_class.create_dialog(dialog_label, terraform_template, extra_vars)
        expect(dialog).to have_attributes(:label => dialog_label, :buttons => "submit,cancel")

        group1 = assert_terraform_template_variables_tab(dialog, :group_size => 1)
        assert_terraform_variables_group(group1, input_vars, :assert_default_value => {:value => "t"})
      end

      it "create_dialog with checkbox field, when default value is empty" do
        input_vars_copy = input_vars.deep_dup
        input_vars_copy[0]['default'] = "" # default attribute is empty
        terraform_template = FactoryBot.create(:terraform_template, :payload => "{\"input_vars\": #{input_vars_copy.to_json}}")

        dialog = described_class.create_dialog(dialog_label, terraform_template, extra_vars)
        expect(dialog).to have_attributes(:label => dialog_label, :buttons => "submit,cancel")

        group1 = assert_terraform_template_variables_tab(dialog, :group_size => 1)
        assert_terraform_variables_group(group1, input_vars_copy, :assert_default_value => {:value => nil})
      end

      it "create_dialog with checkbox field, when default value is not available" do
        input_vars_copy = input_vars.deep_dup
        input_vars_copy[0].delete('default') # no default attribute
        terraform_template = FactoryBot.create(:terraform_template, :payload => "{\"input_vars\": #{input_vars_copy.to_json}}")

        dialog = described_class.create_dialog(dialog_label, terraform_template, extra_vars)
        expect(dialog).to have_attributes(:label => dialog_label, :buttons => "submit,cancel")

        group1 = assert_terraform_template_variables_tab(dialog, :group_size => 1)
        assert_terraform_variables_group(group1, input_vars_copy, :assert_default_value => {:value => nil})
      end
    end
  end

  # -----------------------------------------------------------------------------------------------------------------

  def assert_variables_tab(dialog, group_size: 1)
    tabs = dialog.dialog_tabs
    expect(tabs.size).to eq(1)

    assert_tab_attributes(tabs.first)

    groups = tabs.first.dialog_groups
    expect(groups.size).to eq(group_size)

    group_size > 1 ? groups.second : groups.first
  end

  def assert_terraform_template_variables_tab(dialog, group_size: 1)
    tabs = dialog.dialog_tabs
    expect(tabs.size).to eq(1)

    groups = tabs.first.dialog_groups
    expect(groups.size).to eq(group_size)

    groups.first
  end

  def assert_tab_attributes(tab)
    expect(tab).to have_attributes(:label => "Basic Information", :display => "edit")
  end

  def assert_field(field, klass, attributes)
    expect(field).to be_kind_of klass
    expect(field).to have_attributes(attributes)
  end

  def assert_extra_variables_group(group)
    expect(group).to have_attributes(:label => "Variables", :display => "edit")

    fields = group.dialog_fields
    expect(fields.size).to eq(3)

    assert_field(fields[0], DialogFieldTextBox, :name => 'some_extra_var', :default_value => 'blah', :data_type => 'string')
    assert_field(fields[1], DialogFieldTextBox, :name => 'other_extra_var', :default_value => '{"name":"some_value"}', :data_type => 'string')
    assert_field(fields[2], DialogFieldTextBox, :name => 'array_extra_var', :default_value => '[{"name":"some_value"}]', :data_type => 'string')
  end

  def assert_default_variables_group(group, field_value)
    expect(group).to have_attributes(:label => "Variables", :display => "edit")

    fields = group.dialog_fields
    expect(fields.size).to eq(1)

    assert_field(fields[0], DialogFieldTextBox, :name => 'name', :default_value => field_value, :data_type => 'string')
  end

  def assert_terraform_variables_group(group, input_vars, assert_default_value: nil)
    expect(group).to have_attributes(:label => "Terraform Template Variables", :display => "edit")

    fields = group.dialog_fields
    expect(fields.size).to eq(input_vars.length)

    input_vars.each_with_index do |var, index|
      name, value, required, readonly, _hidden, label, description, data_type = var.values_at(
        "name", "default", "required", "immutable", "hidden", "label", "description", "type"
      )

      value = assert_default_value[:value] if assert_default_value.present?
      description = name if description.blank?

      case data_type
      when 'boolean'
        assert_field(fields[index], DialogFieldCheckBox,
                     :name           => name,
                     :default_value  => value,
                     :data_type      => 'boolean',
                     :label          => name,
                     :description    => description,
                     :reconfigurable => true,
                     :position       => index,
                     :read_only      => readonly)
      else
        assert_field(fields[index], DialogFieldTextBox,
                     :name           => name,
                     :default_value  => value,
                     :data_type      => 'string',
                     :display        => "edit",
                     :required       => required,
                     :label          => label,
                     :description    => description,
                     :reconfigurable => true,
                     :position       => index,
                     :dialog_group   => group,
                     :read_only      => readonly)
      end
    end
  end
end

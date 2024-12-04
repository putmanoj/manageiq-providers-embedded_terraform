require 'terraform/runner'

RSpec.describe(Terraform::Runner::ApiParams) do
  it "add param" do
    params = described_class.add_param([], 'param-value', 'PARAM_NAME')
    expect(params)
      .to(eq(
            [
              {
                'name'    => 'PARAM_NAME',
                'value'   => 'param-value',
                'secured' => 'false',
              }
            ]
          ))
  end

  it "add param, with secure true" do
    params = described_class.add_param_if_present([], 'cGFyYW0tdmFsdWUK', 'PARAM_NAME', :is_secured => true)
    expect(params)
      .to(eq(
            [
              {
                'name'    => 'PARAM_NAME',
                'value'   => 'cGFyYW0tdmFsdWUK',
                'secured' => 'true',
              }
            ]
          ))
  end

  it "not adding param, if nil" do
    params = described_class.add_param_if_present([], nil, 'PARAM_NAME')
    expect(params).to(eq([]))
  end

  it "not adding param, if blank" do
    params = described_class.add_param_if_present([], '', 'PARAM_NAME')
    expect(params).to(eq([]))
  end

  it "adding param, if nil" do
    params = described_class.add_param([], nil, 'PARAM_NAME')
    expect(params)
      .to(eq(
            [
              {
                'name'    => 'PARAM_NAME',
                'value'   => nil,
                'secured' => 'false',
              }
            ]
          ))
  end

  it "not adding param, if blank" do
    params = described_class.add_param([], '', 'PARAM_NAME')
    expect(params)
      .to(eq(
            [
              {
                'name'    => 'PARAM_NAME',
                'value'   => '',
                'secured' => 'false',
              }
            ]
          ))
  end

  it "converts to cam_parameters" do
    params = described_class.to_cam_parameters(
      {
        'region'  => 'us-east',
        'vm_name' => 'vm1',
      }
    )
    expect(params)
      .to(eq(
            [
              {
                'name'    => 'region',
                'value'   => 'us-east',
                'secured' => 'false',
              },
              {
                'name'    => 'vm_name',
                'value'   => 'vm1',
                'secured' => 'false',
              },
            ]
          ))
  end

  describe 'Normalized manageiq vars to cam_parameters' do
    let(:type_constraints) do
      [
        {:name => "a_bool", :label => "a_bool", :type => "boolean", :description => "This a boolean type, with default value", :required => true, :secured => false, :hidden => false, :immutable => false, :default => true},
        {:name => "a_bool_required", :label => "a_bool_required", :type => "boolean", :description => "This a boolean type, value is required to provider from user", :required => true, :secured => false, :hidden => false, :immutable => false},
        {:name => "a_number", :label => "a_number", :type => "number", :description => "This a number type, with default value", :required => true, :secured => false, :hidden => false, :immutable => false, :default => 10},
        {:name => "a_number_required", :label => "a_number_required", :type => "number", :description => "This a number type, value is required to provider from user", :required => true, :secured => false, :hidden => false, :immutable => false},
        {:name => "a_object", :label => "a_object", :type => "map", :description => "", :required => true, :secured => false, :hidden => false, :immutable => false, :default => {:age => 30, :email => "sam@example.com", :name => "Sam"}},
        {:name => "a_object_with_optional_attribute", :label => "a_object_with_optional_attribute", :type => "map", :description => "", :required => true, :secured => false, :hidden => false, :immutable => false, :default => {:user_id => "josh"}},
        {:name => "a_string", :label => "a_string", :type => "string", :description => "This a string type, with default value", :required => true, :secured => false, :hidden => false, :immutable => false, :default => "World"},
        {:name => "a_string_required", :label => "a_string_required", :type => "string", :description => "This a string type, value is required to provider from user", :required => true, :secured => false, :hidden => false, :immutable => false},
        {:name => "a_string_with_sensitive_value", :label => "a_string_with_sensitive_value", :type => "string", :description => "This a string type, with sensitive value", :required => true, :secured => false, :hidden => false, :immutable => false, :default => "The Secret"},
        {:name => "list_of_any_types", :label => "list_of_any_types", :type => "list", :description => "", :required => true, :secured => false, :hidden => false, :immutable => false},
        {:name => "list_of_object_with_nested_structures", :label => "list_of_object_with_nested_structures", :type => "list", :description => "", :required => true, :secured => false, :hidden => false, :immutable => false, :default => [{:name => "Production", :website => {:routing_rules => "[\n  {\n    \"Condition\" = { \"KeyPrefixEquals\": \"img/\" },\n    \"Redirect\"  = { \"ReplaceKeyPrefixWith\": \"images/\" }\n  }\n]\n"}}, {:enabled => false, :name => "archived"}]},
        {:name => "list_of_objects", :label => "list_of_objects", :type => "list", :description => "", :required => true, :secured => false, :hidden => false, :immutable => false, :default => [{:external => 8300, :internal => 8300, :protocol => "tcp"}]},
        {:name => "list_of_strings", :label => "list_of_strings", :type => "list", :description => "", :required => true, :secured => false, :hidden => false, :immutable => false, :default => ["micro", "large", "xlarge"]}
      ]
    end

    it "converts to cam_parameters" do
      input_params = {
        :a_bool          => "T",
        :a_bool_required => "",
        :a_number        => "1",
        :a_object        => "{\"age\": 30, \"email\": \"sam@example.com\", \"name\": \"Sam\"}",
        :list_of_objects => "[{\"external\": 8300, \"internal\": 8300, \"protocol\": \"tcp\"}]",
        :list_of_strings => "[\"a\",\"b\",\"c\"]",
        :extra_var       => "z"
      }

      expect_params = [
        {"name" => "a_bool", "value" => true, "secured" => "false"},
        {"name" => "a_bool_required", "value" => false, "secured" => "false"},
        {"name" => "a_number", "value" => "1", "secured" => "false"},
        {"name" => "a_object", "value" => {"age" => 30, "email" => "sam@example.com", "name" => "Sam"}, "secured" => "false"},
        {"name" => "list_of_objects", "value" => [{"external" => 8300, "internal" => 8300, "protocol" => "tcp"}], "secured" => "false"},
        {"name" => "list_of_strings", "value" => ["a", "b", "c"], "secured" => "false"},
        {"name" => "extra_var", "value" => "z", "secured" => "false"}
      ]

      params = described_class.to_normalized_cam_parameters(input_params, type_constraints)

      expect(params.to_json).to(eq(expect_params.to_json))
    end

    it "fails, if param of type 'list', is not a array-json-string" do
      input_params = {
        :list_of_strings => "a",
      }
      expect { described_class.to_normalized_cam_parameters(input_params, type_constraints) }
        .to raise_error(RuntimeError, "The variable 'list_of_strings' does not have valid array value")
    end

    it "fails, if param of type 'list', is not a array" do
      input_params = {
        :list_of_strings => {},
      }
      expect { described_class.to_normalized_cam_parameters(input_params, type_constraints) }
        .to raise_error(RuntimeError, "The variable 'list_of_strings' does not have valid array value")
    end

    it "fails, if param of type 'map', is not a hashmap-json-string" do
      input_params = {
        :a_object => "\"name\": \"Sam\""
      }
      expect { described_class.to_normalized_cam_parameters(input_params, type_constraints) }
        .to raise_error(RuntimeError, "The variable 'a_object' does not have valid hashmap value")
    end

    it "fails, if param of type 'map', is not a hashmap" do
      input_params = {
        :a_object => [],
      }
      expect { described_class.to_normalized_cam_parameters(input_params, type_constraints) }
        .to raise_error(RuntimeError, "The variable 'a_object' does not have valid hashmap value")
    end
  end
end

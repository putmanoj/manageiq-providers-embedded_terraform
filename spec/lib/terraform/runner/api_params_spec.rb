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
        {"name" => "a_bool", "label" => "a_bool", "type" => "boolean", "description" => "This a boolean type, with default value", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => true},
        {"name" => "a_bool_required", "label" => "a_bool_required", "type" => "boolean", "description" => "This a boolean type, value is required to provider from user", "required" => true, "secured" => false, "hidden" => false, "immutable" => false},
        {"name" => "a_number", "label" => "a_number", "type" => "string", "description" => "This a number type, with default value", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => 10},
        {"name" => "a_number_required", "label" => "a_number_required", "type" => "string", "description" => "This a number type, value is required to provider from user", "required" => true, "secured" => false, "hidden" => false, "immutable" => false},
        {"name" => "a_object", "label" => "a_object", "type" => "map", "description" => "", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => {"age" => 30, "email" => "sam@example.com", "name" => "Sam"}},
        {"name" => "a_object_with_optional_attribute", "label" => "a_object_with_optional_attribute", "type" => "map", "description" => "", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => {"user_id"=>"josh"}},
        {"name" => "a_string", "label" => "a_string", "type" => "string", "description" => "This a string type, with default value", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => "World"},
        {"name" => "a_string_required", "label" => "a_string_required", "type" => "string", "description" => "This a string type, value is required to provider from user", "required" => true, "secured" => false, "hidden" => false, "immutable" => false},
        {"name" => "a_string_with_sensitive_value", "label" => "a_string_with_sensitive_value", "type" => "string", "description" => "This a string type, with sensitive value", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => "The Secret"},
        {"name" => "list_of_any_types", "label" => "list_of_any_types", "type" => "list", "description" => "", "required" => true, "secured" => false, "hidden" => false, "immutable" => false},
        {"name" => "list_of_object_with_nested_structures", "label" => "list_of_object_with_nested_structures", "type" => "list", "description" => "", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => [{"name" => "Production", "website" => {"routing_rules"=>"[\n  {\n    \"Condition\" = { \"KeyPrefixEquals\": \"img/\" },\n    \"Redirect\"  = { \"ReplaceKeyPrefixWith\": \"images/\" }\n  }\n]\n"}}, {"enabled" => false, "name" => "archived"}]},
        {"name" => "list_of_objects", "label" => "list_of_objects", "type" => "list", "description" => "", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => [{"external" => 8300, "internal" => 8300, "protocol" => "tcp"}]},
        {"name" => "list_of_strings", "label" => "list_of_strings", "type" => "list", "description" => "", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => ["micro", "large", "xlarge"]},
        {"name" => "list_of_strings_required", "label" => "list_of_strings_required", "type" => "list", "description" => "This a boolean type, with default value", "required" => true, "secured" => false, "hidden" => false, "immutable" => false},
        {"name" => "map_with_string", "label" => "map_with_string", "type" => "map", "description" => "", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => {"environment" => "dev", "name" => "demo"}},
        {"name" => "set_of_strings", "label" => "set_of_strings", "type" => "list", "description" => "The set type, holding unordered set of unique values", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => ["sg-12345678", "sg-abcdefgh"]},
        {"name" => "tuple_of_all_primitive_types", "label" => "tuple_of_all_primitive_types", "type" => "list", "description" => "The tuple with three different types, which are immutable", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => ["a", 15, true]},
        {"name" => "tuple_of_strings", "label" => "tuple_of_strings", "type" => "list", "description" => "The tuple of all string types, which are immutable", "required" => true, "secured" => false, "hidden" => false, "immutable" => false, "default" => ["192.168.1.1", "192.168.1.2"]}
      ]
    end

    it "converts to cam_parameters" do
      input_params = {
        "a_bool"                                => "t",
        "a_bool_required"                       => "",
        "a_number"                              => "10",
        "a_number_required"                     => "1",
        "a_object"                              => "{\n  \"age\": 30,\n  \"email\": \"sam@example.com\",\n  \"name\": \"Sam\"\n}",
        "a_object_with_optional_attribute"      => "{\n  \"user_id\": \"josh\"\n}",
        "a_string"                              => "World",
        "a_string_required"                     => "a",
        "a_string_with_sensitive_value"         => "The Secret",
        "list_of_any_types"                     => "[1, 2, 3]",
        "list_of_object_with_nested_structures" => "[\n  {\n    \"name\": \"Production\",\n    \"website\": {\n      \"routing_rules\": \"[\\n  {\\n    \\\"Condition\\\" = { \\\"KeyPrefixEquals\\\": \\\"img/\\\" },\\n    \\\"Redirect\\\"  = { \\\"ReplaceKeyPrefixWith\\\": \\\"images/\\\" }\\n  }\\n]\\n\"\n    }\n  },\n  {\n    \"enabled\": false,\n    \"name\": \"archived\"\n  }\n]",
        "list_of_objects"                       => "[\n  {\n    \"external\": 8300,\n    \"internal\": 8300,\n    \"protocol\": \"tcp\"\n  }\n]",
        "list_of_strings"                       => "[\n  \"micro\",\n  \"large\",\n  \"xlarge\"\n]",
        "list_of_strings_required"              => "[\"a\",\"b\",\"c\"]",
        "map_with_string"                       => "{\n  \"environment\": \"dev\",\n  \"name\": \"demo\"\n}",
        "set_of_strings"                        => "[\n  \"sg-12345678\",\n  \"sg-abcdefgh\"\n]",
        "tuple_of_all_primitive_types"          => "[\n  \"a\",\n  15,\n  true\n]",
        "tuple_of_strings"                      => "[\n  \"192.168.1.1\",\n  \"192.168.1.2\"\n]",
        "extra_var"                             => "extra",
      }

      expect_params = [
        {:name => "a_bool", :value => true, :secured => "false"},
        {:name => "a_bool_required", :value => false, :secured => "false"},
        {:name => "a_number", :value => "10", :secured => "false"},
        {:name => "a_number_required", :value => "1", :secured => "false"},
        {:name => "a_object", :value => {:age => 30, :email => "sam@example.com", :name => "Sam"}, :secured => "false"},
        {:name => "a_object_with_optional_attribute", :value => {:user_id => "josh"}, :secured => "false"},
        {:name => "a_string", :value => "World", :secured => "false"},
        {:name => "a_string_required", :value => "a", :secured => "false"},
        {:name => "a_string_with_sensitive_value", :value => "The Secret", :secured => "false"},
        {:name => "list_of_any_types", :value => [1, 2, 3], :secured => "false"},
        {:name => "list_of_object_with_nested_structures", :value => [{:name => "Production", :website => {:routing_rules => "[\n  {\n    \"Condition\" = { \"KeyPrefixEquals\": \"img/\" },\n    \"Redirect\"  = { \"ReplaceKeyPrefixWith\": \"images/\" }\n  }\n]\n"}}, {:enabled => false, :name => "archived"}], :secured => "false"},
        {:name => "list_of_objects", :value => [{:external => 8300, :internal => 8300, :protocol => "tcp"}], :secured => "false"},
        {:name => "list_of_strings", :value => ["micro", "large", "xlarge"], :secured => "false"},
        {:name => "list_of_strings_required", :value => ["a", "b", "c"], :secured => "false"},
        {:name => "map_with_string", :value => {:environment => "dev", :name => "demo"}, :secured => "false"},
        {:name => "set_of_strings", :value => ["sg-12345678", "sg-abcdefgh"], :secured => "false"},
        {:name => "tuple_of_all_primitive_types", :value => ["a", 15, true], :secured => "false"},
        {:name => "tuple_of_strings", :value => ["192.168.1.1", "192.168.1.2"], :secured => "false"},
        {:name => "extra_var", :value => "extra", :secured => "false"}
      ]
      params = described_class.to_normalized_cam_parameters(input_params, type_constraints)

      expect(params.to_json).to(eq(expect_params.to_json))
    end

    it "fails, if param of type 'list', is not a array-json-string" do
      input_params = {
        "list_of_strings" => "a",
      }
      expect { described_class.to_normalized_cam_parameters(input_params, type_constraints) }
        .to raise_error(RuntimeError, "The variable 'list_of_strings' does not have valid array value")
    end

    it "fails, if param of type 'list', is not a array" do
      input_params = {
        "list_of_strings" => {},
      }
      expect { described_class.to_normalized_cam_parameters(input_params, type_constraints) }
        .to raise_error(RuntimeError, "The variable 'list_of_strings' does not have valid array value")
    end

    it "fails, if param of type 'map', is not a hashmap-json-string" do
      input_params = {
        "a_object" => "\"name\": \"Sam\""
      }
      expect { described_class.to_normalized_cam_parameters(input_params, type_constraints) }
        .to raise_error(RuntimeError, "The variable 'a_object' does not have valid hashmap value")
    end

    it "fails, if param of type 'map', is not a hashmap" do
      input_params = {
        "a_object" => [],
      }
      expect { described_class.to_normalized_cam_parameters(input_params, type_constraints) }
        .to raise_error(RuntimeError, "The variable 'a_object' does not have valid hashmap value")
    end

    it "converts boolean value to true" do
      input_params = {
        "a_bool"          => "t",
        "a_bool_required" => true,
      }

      expect_params = [
        {:name => "a_bool", :value => true, :secured => "false"},
        {:name => "a_bool_required", :value => true, :secured => "false"},
      ]

      params = described_class.to_normalized_cam_parameters(input_params, type_constraints)

      expect(params.to_json).to(eq(expect_params.to_json))
    end

    it "converts boolean value to false" do
      input_params = {
        "a_bool"          => "f",
        "a_bool_required" => "",
      }

      expect_params = [
        {:name => "a_bool", :value => false, :secured => "false"},
        {:name => "a_bool_required", :value => false, :secured => "false"},
      ]

      params = described_class.to_normalized_cam_parameters(input_params, type_constraints)

      expect(params.to_json).to(eq(expect_params.to_json))
    end
  end
end

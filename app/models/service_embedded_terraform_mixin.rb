module ServiceEmbeddedTerraformMixin
  extend ActiveSupport::Concern

  # Builds stack options for Terraform operations
  #
  # This method constructs a hash of options needed for Terraform stack operations,
  # combining the action type with input variables from dialog options and any overrides.
  # It also translates credential references into their native format.
  #
  # @param action [String] The action to perform (default: ResourceAction::PROVISION)
  #                        Common values include PROVISION, RETIREMENT, etc.
  # @param overrides [Hash] Additional options to merge with the service options (default: {})
  #
  # @return [Hash] A hash containing:
  #   - :action [String] The action type
  #   - :input_vars [Hash] Input variables extracted from dialog
  #   - :credentials [Array] Array of credential native references
  #
  # @example Building stack options for provisioning
  #   stack_opts(ResourceAction::PROVISION)
  #   # => { action: "Provision", input_vars: {...}, credentials: [...] }
  #
  # @example Building stack options with overrides
  #   stack_opts(ResourceAction::PROVISION, { credential_id: 123 })
  #   # => { action: "Provision", input_vars: {...}, credentials: [credential_ref] }
  def stack_opts(action = ResourceAction::PROVISION, overrides = {})
    stack_opts = {:action => action}.merge(input_vars_from_dialog(options.merge(overrides)))

    if instance_of?(ServiceEmbeddedTerraform)
      stack_opts[:credential_id] = credential_id_from_workflow_provision_request(overrides)
    end

    translate_credentials!(stack_opts)

    stack_opts
  end

  CONFIG_OPTIONS_WHITELIST = %i[
    credential_id
    execution_ttl
    input_vars
    verbosity
  ].freeze

  private

  # Extracts and transforms input variables from service dialog options
  #
  # This method processes dialog options to extract Terraform input variables,
  # removing the "dialog_" prefix and optional "password::" prefix from attribute names.
  #
  # @param service_options [Hash] The service options hash containing dialog data
  # @param only_dialog [Boolean] When true, only processes attributes starting with "dialog_"
  #                               When false, processes all attributes in the dialog hash
  #
  # @return [Hash] A hash with a single :input_vars key containing the transformed variables
  #
  # @example Processing all dialog attributes (only_dialog: false, default)
  #   service_options = {
  #     dialog: {
  #       "dialog_var1" => "value1",
  #       "password::dialog_secret" => "value2",
  #       "other_param" => "value3"
  #     }
  #   }
  #   input_vars_from_dialog(service_options)
  #   # => { input_vars: { "var1" => "value1", "secret" => "value2", "other_param" => "value3" } }
  #
  # @example Processing only dialog-prefixed attributes (only_dialog: true)
  #   service_options = {
  #     dialog: {
  #       "dialog_var1" => "value1",
  #       "password::dialog_secret" => "value2",
  #       "other_param" => "value3"
  #     }
  #   }
  #   input_vars_from_dialog(service_options, only_dialog: true)
  #   # => { input_vars: { "var1" => "value1", "secret" => "value2" } }
  #
  # @example Handling invalid input
  #   input_vars_from_dialog(nil)
  #   # => { input_vars: {} }
  #
  # @note The method strips the following prefixes from attribute names:
  #   - "dialog_" - Standard dialog field prefix
  #   - "password::dialog_" - Password-protected dialog field prefix
  def input_vars_from_dialog(service_options = nil, only_dialog: false)
    # Handle backward compatibility: support both positional and keyword arguments
    # When called as input_vars_from_dialog(action_options, true)
    if service_options.nil?
      service_options = options
    end

    # Validate input parameter
    return {:input_vars => {}} unless service_options.kind_of?(Hash)

    dialog_options = service_options.fetch(:dialog, {})

    input_vars = dialog_options.each_with_object({}) do |(attr, val), result|
      attr_str = attr.to_s

      # Skip non-dialog attributes when only_dialog is true
      next if only_dialog && !attr_str.start_with?("dialog_", "password::dialog_")

      # Extract variable key by removing password:: and dialog_ prefixes
      var_key = attr_str.sub(/\A(?:password::)?dialog_/, '')
      result[var_key] = val unless var_key.empty?
    end

    {:input_vars => input_vars}
  end

  # Translates credential IDs into native credential references
  #
  # This method modifies the options hash in-place, removing the :credential_id key
  # and adding a :credentials array containing the native reference of the credential.
  # If no credential_id is present, an empty credentials array is set.
  #
  # @param options [Hash] The options hash to modify
  #   - :credential_id [Integer, nil] The ID of the credential to translate
  #
  # @return [void] Modifies the options hash in-place
  #
  # @example With a credential ID
  #   options = { credential_id: 123 }
  #   translate_credentials!(options)
  #   # options is now: { credentials: [<native_ref>] }
  #
  # @example Without a credential ID
  #   options = {}
  #   translate_credentials!(options)
  #   # options is now: { credentials: [] }
  #
  # @note This method mutates the input hash by:
  #   - Removing the :credential_id key
  #   - Adding a :credentials key with an array value
  def translate_credentials!(options)
    options[:credentials] = []

    credential_id = options.delete(:credential_id)
    options[:credentials] << Authentication.find(credential_id).native_ref if credential_id.present?
  end

  # Extracts whitelisted configuration options for a specific action
  #
  # This method retrieves configuration options from the service's config_info hash
  # for a given action, filtering them to only include whitelisted options defined
  # in CONFIG_OPTIONS_WHITELIST.
  #
  # @param action [String] The action name (e.g., "Provision", "Retirement")
  #                        Will be converted to lowercase symbol for lookup
  #
  # @return [ActiveSupport::HashWithIndifferentAccess, nil]
  #   A hash containing only whitelisted config options if config_info exists,
  #   nil if config_info is not present in options
  #
  # @example Retrieving provision config options
  #   # Assuming options = { config_info: { provision: { credential_id: 1, verbosity: 2, other: 3 } } }
  #   config_options!("Provision")
  #   # => { "credential_id" => 1, "verbosity" => 2 }
  #
  # @example When config_info is not present
  #   # Assuming options = {}
  #   config_options!("Provision")
  #   # => nil
  #
  # @note Only options listed in CONFIG_OPTIONS_WHITELIST are returned:
  #   - credential_id
  #   - execution_ttl
  #   - input_vars
  #   - verbosity
  def config_options!(action)
    options.fetch_path(:config_info, action.downcase.to_sym).slice(*CONFIG_OPTIONS_WHITELIST).with_indifferent_access if options.key?(:config_info)
  end

  def credential_id_from_workflow_provision_request(request_options)
    credential_id = request_options[:credential_id]

    # If for provision_workflow, coming from customize tab, it will have a array like [id, name], and we only take id
    credential_id = credential_id.first if credential_id.kind_of?(Array) && credential_id.first.present?

    credential_id
  end
end

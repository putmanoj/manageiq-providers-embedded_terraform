module Terraform
  class Runner
    class Request
      include Vmdb::Logging

      attr_reader :options, :action_type

      # Create new Request
      #
      # @param action_type [String] action to run, use one of Terraform::Runner::ActionType::<constant>
      # @param options     [Hash]   key/values pairs
      def initialize(action_type, options)
        @action_type = action_type
        @options = options
      end

      def build_json_post_arguments
        validate
        json_post_arguments(build_arguments)
      end

      def validate
        case @action_type
        when ActionType::CREATE, ActionType::TEMPLATE_VARIABLES
          # 'templateZipFile' is added, if 'template_path' is set
          raise "'template_path' is required for #{@action_type}" unless option?(:template_path)
        when ActionType::UPDATE, ActionType::DELETE
          raise "'stack_id' and 'template_path' are required for #{@action_type}" unless option?(:template_path) && option?(:stack_id)
        when ActionType::CANCEL, ActionType::RETRIEVE
          raise "'stack_id' is required for #{@action_type}" unless option?(:stack_id)
        else
          raise "Invalid action_type: #{@action_type}"
        end
      end

      private

      def option?(option_name)
        @options.key?(option_name) && !@options[option_name].nil?
      end

      def build_arguments
        arguments = {}
        arguments[:name] = @options[:name] if option?(:name)
        arguments[:stack_id] = @options[:stack_id] if option?(:stack_id)
        arguments[:stack_job_id] = @options[:stack_job_id] if option?(:stack_job_id)
        arguments[:tenant_id] = @options[:tenant_id] if option?(:tenant_id)
        arguments[:tags] = @options[:tags] if option?(:tags)
        arguments[:env_vars] = @options[:env_vars] if option?(:env_vars)

        if option?(:credentials)
          arguments[:cloud_providers] =
            provider_connection_parameters(options[:credentials])
        end
        if option?(:template_path)
          arguments[:templateZipFile] =
            encoded_zip_from_directory(options[:template_path])
        end
        if option?(:input_vars)
          arguments[:parameters] = ApiParams.to_normalized_cam_parameters(
            @options[:input_vars], @options[:input_vars_type_constraints]
          )
        end

        case @action_type
        when ActionType::CREATE
          arguments[:name] ||= random_stack_name
          arguments[:cloud_providers] ||= []
          arguments[:parameters] ||= []
        when ActionType::UPDATE, ActionType::DELETE
          arguments[:cloud_providers] ||= []
          arguments[:parameters] ||= []
        end

        arguments
      end

      def json_post_arguments(request_arguments)
        return JSON.generate(request_arguments), "Content-Type" => "application/json".freeze
      end

      def provider_connection_parameters(credentials)
        credentials.collect do |cred|
          {
            'connection_parameters' => Terraform::Runner::Credential.new(cred.id).connection_parameters
          }
        end
      end

      # encode zip of a template directory
      def encoded_zip_from_directory(template_path)
        if !File.directory?(template_path)
          raise "Terraform template path '#{template_path}' does not exits"
        end

        dir_path = template_path # directory to be zipped
        dir_path = dir_path[0...-1] if dir_path.end_with?('/')

        Tempfile.create(%w[opentofu-runner-payload .zip]) do |zip_file_path|
          $embedded_terraform_log.debug("Create #{zip_file_path}")
          Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
            Dir.glob(File.join(dir_path, "/**/*")).select { |fn| File.file?(fn) }.each do |file|
              $embedded_terraform_log.debug("Adding #{file}")
              zipfile.add(file.sub("#{dir_path}/", ''), file)
            end
          end
          Base64.encode64(File.binread(zip_file_path))
        end
      end

      def random_stack_name
        "stack-#{rand(36**8).to_s(36)}"
      end
    end
  end
end

module TerraformEvmSpecHelper
  extend RSpec::Mocks::ExampleMethods

  def self.assign_embedded_terraform_role(miq_server = nil)
    assign_role("embedded_terraform", :miq_server => miq_server, :create_options => {:max_concurrent => 0})
  end
end

class ServiceEmbeddedTerraform < Service
  def stack(action)
    service_resources.find_by(:name => action, :resource_type => 'OrchestrationStack').try(:resource)
  end
end

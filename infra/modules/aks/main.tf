resource "azurerm_kubernetes_cluster" "main" {
  name                = "dev-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "dev-aks"

  default_node_pool {
    name           = "default"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.vnet_subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  linux_profile {
    admin_username = "azureuser"

    ssh_key {
      key_data = file(var.ssh_public_key_path)
    }
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_id
  }

  role_based_access_control_enabled = true

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.1.0.0/16"
    dns_service_ip = "10.1.0.10"
  }


  api_server_access_profile {
    authorized_ip_ranges = var.api_authorized_ip_ranges
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                            = var.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

output "name" {
  value = azurerm_kubernetes_cluster.main.name
}



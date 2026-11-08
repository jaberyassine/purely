resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${var.name}-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Grant custom-subnet access before cluster creation, rather than relying on CLI
# implicit grants (Terraform creates the cluster through the Azure API).
resource "azurerm_role_assignment" "subnet_network" {
  scope                            = var.vnet_subnet_id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  sku_tier            = "Free"
  oidc_issuer_enabled = true
  tags                = var.tags
  depends_on          = [azurerm_role_assignment.subnet_network]

  default_node_pool {
    name            = "default"
    node_count      = var.node_count
    vm_size         = var.node_vm_size
    vnet_subnet_id  = var.vnet_subnet_id
    max_pods        = 30
    os_sku          = "Ubuntu"
    os_disk_type    = "Managed"
    os_disk_size_gb = 128
    tags            = var.tags
    # Preserve Azure's current defaults; this does not initiate an upgrade.
    # A third 4-vCPU surge node still requires an increased DSv4 family quota.
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
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
    network_plugin    = "azure"
    service_cidr      = "10.1.0.0/16"
    dns_service_ip    = "10.1.0.10"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
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
output "id" {
  value = azurerm_kubernetes_cluster.main.id
}
output "node_resource_group" {
  value = azurerm_kubernetes_cluster.main.node_resource_group
}



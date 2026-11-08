resource "azurerm_log_analytics_workspace" "main" {
  name                = "dev-log-analytics"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

output "workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

variable "resource_group_name" {}
variable "location" {}
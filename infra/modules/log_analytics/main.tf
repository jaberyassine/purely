resource "azurerm_log_analytics_workspace" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.daily_quota_gb
  tags                = var.tags
}

output "workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

variable "resource_group_name" {}
variable "location" {}
variable "name" { type = string }
variable "daily_quota_gb" { type = number }
variable "tags" { type = map(string) }

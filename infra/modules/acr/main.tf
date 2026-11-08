resource "azurerm_container_registry" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}


output "acr_id" {
  value = azurerm_container_registry.main.id
}

variable "resource_group_name" {}
output "login_server" {
  value = azurerm_container_registry.main.login_server
}
variable "location" {}
variable "name" { type = string }
variable "tags" { type = map(string) }

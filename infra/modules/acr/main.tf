resource "azurerm_container_registry" "main" {
  name                = "purelyacr"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
}


output "acr_id" {
  value = azurerm_container_registry.main.id
}

variable "resource_group_name" {}
output "login_server" {
  value = azurerm_container_registry.main.login_server
}
variable "location" {}

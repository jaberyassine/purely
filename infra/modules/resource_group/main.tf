resource "azurerm_resource_group" "main" {
  name     = "dev-rg"
  location = "East US"
}

output "name" {
  value = azurerm_resource_group.main.name
}

output "location" {
  value = azurerm_resource_group.main.location
}
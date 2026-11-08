output "resource_group_name" {
  value = module.resource_group.name
}
output "aks_name" {
  value = module.aks.name
}
output "acr_login_server" {
  value = module.acr.login_server
}
output "aks_id" {
  value = module.aks.id
}
output "node_resource_group_name" {
  value = module.aks.node_resource_group
}
output "aks_dns_service_ip" {
  value = "10.1.0.10"
}

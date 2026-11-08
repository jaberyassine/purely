variable "resource_group_name" {}
variable "location" {}
variable "vnet_subnet_id" {}
variable "log_analytics_id" {}
variable "acr_id" {}
variable "ssh_public_key_path" { type = string }
variable "node_count" { type = number }
variable "node_vm_size" { type = string }
variable "api_authorized_ip_ranges" { type = list(string) }

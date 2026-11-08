variable "subscription_id" {
  type        = string
  description = "Authenticate through Azure CLI or ARM OIDC environment variables."
}
variable "tenant_id" { type = string }
variable "resource_group_name" {
  type    = string
  default = "dev-rg"
}
variable "location" {
  type    = string
  default = "eastus"
}
variable "cluster_name" {
  type    = string
  default = "dev-aks"
}
variable "network_name_prefix" {
  type    = string
  default = "dev"
}
variable "log_analytics_name" {
  type    = string
  default = "dev-log-analytics"
}
variable "log_daily_quota_gb" {
  type        = number
  description = "Daily Log Analytics ingestion cap; not a hard billing limit. Some data can be exempt or arrive before enforcement."
  default     = 1
  validation {
    condition     = var.log_daily_quota_gb >= 1
    error_message = "Set an explicit daily ingestion cap of at least 1 GB."
  }
}
variable "tags" {
  type    = map(string)
  default = { environment = "demo", purpose = "interview-evidence" }
}
variable "acr_name" {
  type        = string
  description = "Globally unique Azure Container Registry name."
  default     = "purelyacr"
  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "ACR names must contain 5-50 alphanumeric characters."
  }
}
variable "skip_provider_registration" {
  type        = bool
  description = "Set true when the required providers have been explicitly registered."
  default     = false
}
variable "ssh_public_key_path" {
  type        = string
  description = "Path to an existing SSH public key; never a private key."
}
variable "node_count" {
  type    = number
  default = 2
  validation {
    condition     = var.node_count >= 2 && floor(var.node_count) == var.node_count
    error_message = "Use at least two nodes for the availability demonstration."
  }
}
variable "node_vm_size" {
  type    = string
  default = "Standard_D4s_v4"
}
variable "api_authorized_ip_ranges" {
  type        = list(string)
  description = "Trusted operator public CIDRs for the AKS API."
  validation {
    condition     = length(var.api_authorized_ip_ranges) > 0 && alltrue([for cidr in var.api_authorized_ip_ranges : can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0" && cidr != "::/0"])
    error_message = "Supply explicit trusted CIDRs; unrestricted access is not accepted."
  }
}

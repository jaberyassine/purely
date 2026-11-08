variable "subscription_id" {
  type        = string
  description = "Authenticate through Azure CLI or ARM OIDC environment variables."
}
variable "tenant_id" { type = string }
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
  default = "Standard_D2s_v5"
}
variable "api_authorized_ip_ranges" {
  type        = list(string)
  description = "Trusted operator public CIDRs for the AKS API."
  validation {
    condition     = length(var.api_authorized_ip_ranges) > 0 && alltrue([for cidr in var.api_authorized_ip_ranges : can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0" && cidr != "::/0"])
    error_message = "Supply explicit trusted CIDRs; unrestricted access is not accepted."
  }
}

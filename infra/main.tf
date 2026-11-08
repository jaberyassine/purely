terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

module "resource_group" {
  source = "./modules/resource_group"
}

module "vnet" {
  source              = "./modules/vnet"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
}

module "acr" {
  source              = "./modules/acr"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
}

module "log_analytics" {
  source              = "./modules/log_analytics"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
}

module "aks" {
  source                   = "./modules/aks"
  resource_group_name      = module.resource_group.name
  location                 = module.resource_group.location
  vnet_subnet_id           = module.vnet.subnet_id
  log_analytics_id         = module.log_analytics.workspace_id
  acr_id                   = module.acr.acr_id
  ssh_public_key_path      = var.ssh_public_key_path
  node_count               = var.node_count
  node_vm_size             = var.node_vm_size
  api_authorized_ip_ranges = var.api_authorized_ip_ranges
}

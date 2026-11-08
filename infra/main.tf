terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

locals {
  tags = merge(var.tags, { project = "purely", managed_by = "terraform" })
}

provider "azurerm" {
  skip_provider_registration = var.skip_provider_registration
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

module "resource_group" {
  source   = "./modules/resource_group"
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

module "vnet" {
  source              = "./modules/vnet"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  name_prefix         = var.network_name_prefix
  tags                = local.tags
}

module "acr" {
  source              = "./modules/acr"
  name                = var.acr_name
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  tags                = local.tags
}

module "log_analytics" {
  source              = "./modules/log_analytics"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  name                = var.log_analytics_name
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
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
  name                     = var.cluster_name
  tags                     = local.tags
}

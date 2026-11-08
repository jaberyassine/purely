variable "enable_github_release_identity" {
  type        = bool
  default     = false
  description = "Create an OIDC identity restricted to this repository's release environment and ACR."
}

resource "azurerm_user_assigned_identity" "github_release" {
  count               = var.enable_github_release_identity ? 1 : 0
  name                = "${var.cluster_name}-github-release"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github_release" {
  count               = var.enable_github_release_identity ? 1 : 0
  name                = "github-release-environment"
  resource_group_name = module.resource_group.name
  parent_id           = azurerm_user_assigned_identity.github_release[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:jaberyassine/purely:environment:release"
}

resource "azurerm_role_assignment" "github_acr_push" {
  count                            = var.enable_github_release_identity ? 1 : 0
  scope                            = module.acr.acr_id
  role_definition_name             = "AcrPush"
  principal_id                     = azurerm_user_assigned_identity.github_release[0].principal_id
  skip_service_principal_aad_check = true
}

output "github_release_configuration" {
  description = "Non-secret GitHub Actions configuration. Protect the release environment and restrict it to master."
  value = var.enable_github_release_identity ? {
    AZURE_CLIENT_ID       = azurerm_user_assigned_identity.github_release[0].client_id
    AZURE_TENANT_ID       = var.tenant_id
    AZURE_SUBSCRIPTION_ID = var.subscription_id
    ACR_NAME              = var.acr_name
    ACR_LOGIN_SERVER      = module.acr.login_server
  } : null
}

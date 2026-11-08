# GitHub release identity for the temporary AKS demo

The application release workflow uses the GitHub environment `release` and
Azure Login with OIDC. The Azure identity must trust exactly
`repo:jaberyassine/purely:environment:release`, issued by
`https://token.actions.githubusercontent.com`, with audience
`api://AzureADTokenExchange`.

Enable `enable_github_release_identity` in the authoritative Desktop Terraform
inputs. `infra/github-release.tf` then manages a user-assigned identity,
federated identity credential and AcrPush assignment scoped to this ACR only.
It grants no AKS access and creates no client secret. Review a saved plan;
the expected addition to the existing infrastructure is three resources.

After apply, `terraform output -json github_release_configuration` provides
the five non-secret Azure/ACR variables required by the release environment.
Also configure `SONAR_ORGANIZATION` (the current frontend configuration uses
`jaberyassine`) and a valid `SONAR_TOKEN` secret. Verify project keys and
quality gates before starting the release. Never paste the token into chat.

In GitHub, restrict the `release` environment to `master`. OIDC environment
subjects authenticate the environment, so its deployment branch rules are
important. Configure repository variable `ACR_LOGIN_SERVER` too, because the
GitOps proposal job does not use the release environment. Allow GitHub Actions
to create pull requests under repository workflow permissions.

Keep existing quality and vulnerability gates enabled. Run the release workflow
on master, review and merge its image-version PR, then reconcile with Argo CD
after database, secrets, TLS and monitoring prerequisites are ready.

The identity remains in the same Terraform state as the cluster so final demo
cleanup also removes its federated trust and registry role assignment.

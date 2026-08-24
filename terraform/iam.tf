# Creates one dedicated Cloud Run runtime identity for each environment.

# for_each turns the environment model into independently addressable service
# accounts. Cloud Run uses these identities instead of the default Compute
# Engine account, isolating application permissions between dev and prod.

resource "google_service_account" "environment_runtime" {
  for_each = local.environments

  project      = var.project_id
  account_id   = each.value.runtime_service_account_id
  display_name = "Cloud Native API ${each.key} runtime"
  description  = "Identity used by the ${each.key} Cloud Run service at runtime."
}

# Creates one GitHub Actions deployment identity for each environment.

# The accounts are intentionally permissionless at creation time. Scoped Cloud
# Run, runtime-impersonation, registry, and WIF grants are managed separately.

resource "google_service_account" "environment_deployer" {
  for_each = local.environments

  project      = var.project_id
  account_id   = each.value.deployer_service_account_id
  display_name = "GitHub Actions ${each.key} Cloud Run deployer"
  description  = "Identity impersonated by GitHub Actions to deploy the ${each.key} Cloud Run service."
}

# Manages the identity impersonated by GitHub Actions to publish images.

# The current project service account is adopted with terraform import. Its
# Workload Identity Federation trust and Artifact Registry permissions are
# separate IAM resources and are managed independently.

resource "google_service_account" "publisher" {
  project      = var.project_id
  account_id   = var.publisher_service_account_id
  display_name = "GitHub Actions Artifact Registry publisher"
}

# Manages the namespace used to represent GitHub identities in Google Cloud.

# The pool alone grants no permissions and validates no tokens. Its OIDC
# provider and service-account impersonation binding are separate resources.

resource "google_iam_workload_identity_pool" "github_actions" {
  project                   = data.google_project.current.number
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = "GitHub Actions"
  disabled                  = false
}

# Validates GitHub-issued OIDC tokens and maps their claims to Google attributes.

# The environment attribute translates the trusted GitHub refs into stable IAM
# selector values. The condition admits only main and develop from this repository;
# branch-scoped service-account bindings keep their permissions separated.

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = data.google_project.current.number
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = var.workload_identity_provider_id
  display_name                       = "GitHub OIDC"
  disabled                           = false

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.environment"      = "assertion.ref == 'refs/heads/${local.environments.development.github_branch}' ? 'development' : (assertion.ref == 'refs/heads/${local.environments.production.github_branch}' ? 'production' : 'unauthorized')"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  attribute_condition = "assertion.repository == '${var.github_repository}' && (assertion.ref == 'refs/heads/${local.environments.development.github_branch}' || assertion.ref == 'refs/heads/${local.environments.production.github_branch}')"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allows the trusted GitHub repository identity to impersonate the publisher.

# A member-level resource manages only this additive grant instead of replacing
# the service account's complete IAM policy.

resource "google_service_account_iam_member" "github_publisher_impersonation" {
  service_account_id = google_service_account.publisher.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions.workload_identity_pool_id}/attribute.repository/${var.github_repository}"
}

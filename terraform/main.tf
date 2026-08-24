# Reads the current project metadata without managing the project itself.

# Workload Identity Federation APIs represent their parent project with its
# immutable numeric identifier, so WIF resources consume the number read here.

data "google_project" "current" {
  project_id = var.project_id
}

# Defines the names of the application secrets.

# Stable logical keys keep the Terraform resource addresses unchanged even if
# a Google Cloud secret ID is renamed later.

locals {
  application_secret_ids = {
    database_url      = "${var.service_name}-database-url"
    database_username = "${var.service_name}-database-username"
    database_password = "${var.service_name}-database-password"
  }

  # Describes the two Phase 10 environments without creating resources by
  # itself. Resources opt into this model explicitly through for_each.
  environments = {
    development = {
      github_branch               = "develop"
      service_name                = "${var.service_name}-dev"
      runtime_service_account_id  = "${var.service_name}-dev-runtime"
      deployer_service_account_id = "github-cloud-run-dev-deployer"
      # Keep the version of each secret independent so that rotating one value
      # does not require creating matching versions for the other two secrets.
      database_secret_versions = {
        database_url      = "1"
        database_username = "1"
        database_password = "1"
      }
      secret_deletion_protection    = false
      cloud_run_deletion_protection = false
    }

    production = {
      github_branch               = "main"
      service_name                = "${var.service_name}-prod"
      runtime_service_account_id  = "${var.service_name}-prod-runtime"
      deployer_service_account_id = "github-cloud-run-prod-deployer"
      # Keep the version of each secret independent so that rotating one value
      # does not require creating matching versions for the other two secrets.
      database_secret_versions = {
        database_url      = "1"
        database_username = "1"
        database_password = "1"
      }
      secret_deletion_protection    = true
      cloud_run_deletion_protection = true
    }
  }

  # Maps each Spring datasource value to the suffix used by its Secret Manager
  # container. These are identifiers only; no secret payload is stored here.
  database_secret_suffixes = {
    database_url      = "database-url"
    database_username = "database-username"
    database_password = "database-password"
  }

  # Produces one flat entry per environment and datasource value. The composite
  # key gives for_each six stable Terraform instances such as
  # "development.database_url" and "production.database_password".
  environment_database_secrets = merge([
    for environment_name, environment in local.environments : {
      for secret_name, secret_suffix in local.database_secret_suffixes :
      "${environment_name}.${secret_name}" => {
        environment  = environment_name
        logical_name = secret_name
        secret_id    = "${environment.service_name}-${secret_suffix}"
      }
    }
  ]...)
}

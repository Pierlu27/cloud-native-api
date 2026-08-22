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
}

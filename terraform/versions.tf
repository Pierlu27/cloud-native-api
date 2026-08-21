terraform {
  # Compatible-version constraints allow non-breaking updates within the
  # selected release line. .terraform.lock.hcl records the exact provider build.

  required_version = "~> 1.15.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.43"
    }
  }
}

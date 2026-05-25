terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Usa Application Default Credentials: gcloud auth application-default login
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

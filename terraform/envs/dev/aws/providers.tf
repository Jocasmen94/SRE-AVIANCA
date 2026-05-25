terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Usa credenciales de `aws configure` — no se definen keys en el código
provider "aws" {
  region = var.aws_region
}

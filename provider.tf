# Please setup your backend , this is example for AWS S3
terraform {
  backend "s3" {
    bucket         = "cp-test-terraform-state"
    key            = "state/terrafrom.tf_state"
    region         = "eu-central-1"
    dynamodb_table = "cp_test_tf_lock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

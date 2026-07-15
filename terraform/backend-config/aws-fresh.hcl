# terraform init -backend-config=backend-config/aws-fresh.hcl
#
# Customer-specific values — never commit real bucket names/keys for a
# specific customer to a shared repo; this file is a template to be copied
# and filled in per deployment.

bucket         = "REPLACE-ME-e2b-sre-tfstate-<account-id>"
key            = "aws-fresh/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "REPLACE-ME-e2b-sre-tflock"
encrypt        = true

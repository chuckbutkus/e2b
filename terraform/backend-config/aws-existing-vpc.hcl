# terraform init -backend-config=backend-config/aws-existing-vpc.hcl
bucket         = "REPLACE-ME-e2b-sre-tfstate-<account-id>"
key            = "aws-existing-vpc/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "REPLACE-ME-e2b-sre-tflock"
encrypt        = true

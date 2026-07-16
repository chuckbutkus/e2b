# terraform init -backend-config=backend-config/gcp-fresh.hcl
#
# Customer-specific values — never commit a real bucket name for a
# specific customer to a shared repo; this file is a template to be
# copied and filled in per deployment.

bucket = "REPLACE-ME-e2b-sre-tfstate-<project-id>"
prefix = "gcp-fresh"

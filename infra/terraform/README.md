# Butterfly Room Terraform

This directory contains the staging infrastructure definition. It intentionally does not import or manage the production VPC, subnet, ALB, listeners, hosted zone, or RDS instance.

## State bootstrap choices

The initial workflow uses local state because no backend resources are created in this change.

1. Run this staging configuration with local state once, after reviewing the plan, and separately create a versioned, encrypted state bucket with a lock mechanism.
2. Have an authorized operator create the state bucket and lock mechanism in the AWS console before the first apply.

After either option, add an `s3` backend block and migrate state with `terraform init -migrate-state`. Never commit backend credentials, local state, `terraform.tfvars`, or plan files.

See [bootstrap/README.md](bootstrap/README.md) for the required backend properties.

## Commands

Run from `environments/staging`:

```powershell
$env:AWS_PROFILE = "butterfly-room-staging"
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform plan -var-file="terraform.tfvars"
```

The provider also pins the required profile, region, and account ID. `terraform apply` and `terraform destroy` are outside this preparation work.

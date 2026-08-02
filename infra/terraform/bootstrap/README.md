# Terraform state backend bootstrap

No backend resource is defined or created by this repository yet. Before team use, an authorized operator should create a dedicated state bucket and configure:

- Region `ap-northeast-1`
- Block Public Access enabled
- Bucket owner enforced
- Versioning enabled
- Server-side encryption enabled
- Access limited to the staging deployer and break-glass administrators
- State locking using an S3 lock file or a dedicated DynamoDB lock table, according to the installed Terraform version
- CloudTrail data-event logging if required by the organization

Do not reuse `butterfly-room-staging`, because application objects and Terraform state have different access and retention requirements. Record the backend bucket name outside source control until its disclosure policy is approved.

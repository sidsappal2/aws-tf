# aws-tf

AWS Terraform infrastructure repository.

## Infrastructure Components

This configuration creates:

- **S3 Bucket `vis-ha-1`**: Located in us-east-1 region
- **S3 Bucket `vis-ha-2`**: Located in us-west-2 region
- **Lambda Function**: `s3_copy_to_west` - Copies objects from east bucket to west bucket
- **IAM Role**: `lambda_s3_copy_role` with necessary S3 and CloudWatch permissions

### S3 Event Trigger

The Lambda function is triggered when objects are created in the `vis-ha-1` bucket. Objects are copied to `vis-ha-2` with the prefix `file.trigger/`.

### Usage

```bash
terraform init
terraform plan
terraform apply
```
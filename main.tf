# Provider configuration
provider "aws" {
  alias  = "east"
  region = "us-east-1"
}

provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

# S3 bucket in us-east-1
resource "aws_s3_bucket" "vis_ha_1" {
  provider = aws.east
  bucket   = "vis-ha-1"
}

# S3 bucket in us-west-2
resource "aws_s3_bucket" "vis_ha_2" {
  provider = aws.west
  bucket   = "vis-ha-2"
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_s3_copy_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM policy for Lambda to access S3 buckets
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda_s3_copy_policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.vis_ha_1.arn}/*",
          "${aws_s3_bucket.vis_ha_2.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content = <<EOF
import json
import boto3
import urllib.parse

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    # Get bucket and object information from the event
    source_bucket = event['Records'][0]['s3']['bucket']['name']
    source_key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')

    # Define destination bucket (us-west-2)
    dest_bucket = 'vis-ha-2'
    dest_key = f"file.trigger/{source_key}"

    try:
        # Copy object from source to destination
        copy_source = {
            'Bucket': source_bucket,
            'Key': source_key
        }

        s3_client.copy_object(
            CopySource=copy_source,
            Bucket=dest_bucket,
            Key=dest_key
        )

        print(f"Successfully copied {source_key} to {dest_bucket}/{dest_key}")

        return {
            'statusCode': 200,
            'body': json.dumps(f"Successfully copied {source_key} to {dest_bucket}")
        }

    except Exception as e:
        print(f"Error copying object: {str(e)}")
        raise e
EOF
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "s3_copy_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3_copy_to_west"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 300

  depends_on = [
    aws_iam_role_policy.lambda_s3_policy,
    data.archive_file.lambda_zip
  ]
}

# Lambda permission for S3 to invoke
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_copy_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.vis_ha_1.arn
}

# S3 bucket notification for Lambda trigger
resource "aws_s3_bucket_notification" "bucket_notification" {
  provider = aws.east
  bucket   = aws_s3_bucket.vis_ha_1.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_copy_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ""
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}
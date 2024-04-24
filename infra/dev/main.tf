terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.45.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.2.0"
    }
  }
}

provider "aws" {
  region     = "ap-northeast-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

locals {
  project_name = "s-s3-lambda-trigger-${var.env}"
}

#================================================================
# イベント通知用のS3バケット
#================================================================
resource "aws_s3_bucket" "original" {
  bucket        = "${local.project_name}-original-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "original" {
  bucket                  = aws_s3_bucket.original.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#================================================================
# 処理済みファイル用ののS3バケット
#================================================================
resource "aws_s3_bucket" "processed" {
  bucket        = "${local.project_name}-processed-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#================================================================
# Lambda用のIAMロールとポリシー
#================================================================

resource "aws_iam_policy" "lambda_policy" {
  name   = "${local.project_name}-lambda-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject"
        ],
        "Resource" : "${aws_s3_bucket.original.arn}/*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject"
        ],
        "Resource" : "${aws_s3_bucket.processed.arn}/*"
      }
    ]
  })
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${local.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach_lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach_lambda_app" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

#================================================================
# Lambda関数
#================================================================
data "archive_file" "lambda_trigger_func_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/s3-trigger"
  output_path = "${path.module}/lambda_trigger_func.zip"
}

resource "aws_lambda_function" "lambda_trigger_func" {
  filename      = "lambda_trigger_func.zip"
  function_name = "${local.project_name}-func"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 30
  environment {
    variables = {
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
    }
  }

  source_code_hash = data.archive_file.lambda_trigger_func_zip.output_base64sha256
}

resource "aws_lambda_permission" "allow_bucket_notification" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_trigger_func.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.original.arn
}

#================================================================
# S3バケットのイベント通知設定
#================================================================
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.original.bucket

  lambda_function {
    id                  = "${local.project_name}-lambda-trigger"
    lambda_function_arn = aws_lambda_function.lambda_trigger_func.arn
    events              = ["s3:ObjectCreated:Put"]
  }
}

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
  project_name = "s-lambda-s3-trigger-${var.env}"
}

resource "aws_s3_bucket" "bucket" {
  bucket        = "${local.project_name}-bucket"
  force_destroy = true
}

#================================================================
# Lambda
#================================================================
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
  name               = "${local.project_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

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

  source_code_hash = data.archive_file.lambda_trigger_func_zip.output_base64sha256
}

terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "deploy-lambdas-terraform-state"
    key            = "lambda-go/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = "us-east-1" }

# Obtenemos el ARN del rol creado por la carpeta infra
data "aws_iam_role" "shared_role" {
  name = "go_lambda_execution_role_shared"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../bootstrap" # Sube un nivel para encontrar el binario
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "go_lambda" {
  function_name    = "users-crud-lambda"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "bootstrap"
  runtime          = "provided.al2023"
  role             = data.aws_iam_role.shared_role.arn
  architectures    = ["arm64"]

  environment {
    variables = {
      TABLE_NAME = "UsersTable"
    }
  }
}
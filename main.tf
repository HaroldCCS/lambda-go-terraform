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
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "bootstrap" 
  output_path = "lambda_function.zip"
}

# 1. Definición de la Tabla DynamoDB
resource "aws_dynamodb_table" "users_table" {
  name           = "UsersTable"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "userId"

  attribute {
    name = "userId"
    type = "S"
  }
}

# 2. Política para que la Lambda acceda a DynamoDB
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "LambdaDynamoDBPolicy"
  description = "Permite a la lambda acceder a la tabla de usuarios"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.users_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# 3. Actualización de la Lambda (Añadir variable de entorno)
resource "aws_lambda_function" "go_lambda" {
  function_name    = "users-crud-lambda"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "bootstrap"
  runtime          = "provided.al2023"
  role             = aws_iam_role.lambda_exec.arn
  architectures    = ["arm64"]

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.users_table.name
    }
  }
}
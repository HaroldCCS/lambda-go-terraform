terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "deploy-lambdas-terraform-state"
    key            = "infra/terraform.tfstate" # Key diferente para no chocar
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = "us-east-1" }

# Tabla DynamoDB
resource "aws_dynamodb_table" "users_table" {
  name           = "UsersTable"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "userId"
  attribute { name = "userId"; type = "S" }
}

# Rol de ejecución para la Lambda
resource "aws_iam_role" "lambda_exec_shared" {
  name = "go_lambda_execution_role_shared"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Permisos: Logs + DynamoDB
resource "aws_iam_role_policy_attachment" "basic_exec" {
  role       = aws_iam_role.lambda_exec_shared.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "dynamo_crud_policy" {
  name = "LambdaDynamoCRUDPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Scan"]
      Effect   = "Allow"
      Resource = aws_dynamodb_table.users_table.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dynamo_attach" {
  role       = aws_iam_role.lambda_exec_shared.name
  policy_arn = aws_iam_policy.dynamo_crud_policy.arn
}
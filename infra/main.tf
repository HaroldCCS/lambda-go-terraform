/*
ROLES CREADOS:
go_lambda_execution_role_shared

POLITICAS CREADAS:
LambdaDynamoCRUDPolicy
LambdaSQSPolicy

API GATEWAY:
UsersCRUD-API


SQS:
user-creation-queue

*/

terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "deploy-lambdas-terraform-state"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1" # Nota: El backend de S3 no acepta variables directas, debe ser string
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
  region = var.aws_region
}

# ----------------------------------- START Database set up (DYNAMODB) -----------------------------------
resource "aws_dynamodb_table" "users_table" {
  name         = "UsersTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }
}

# --- 2. SEGURIDAD E IAM (ROLES Y POLÍTICAS) ---
resource "aws_iam_role" "lambda_exec_shared" {
  name = "go_lambda_execution_role_shared"
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

resource "aws_iam_role_policy_attachment" "basic_exec" {
  role       = aws_iam_role.lambda_exec_shared.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "dynamo_crud_policy" {
  name = "LambdaDynamoCRUDPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan"
      ]
      Effect   = "Allow"
      Resource = aws_dynamodb_table.users_table.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dynamo_attach" {
  role       = aws_iam_role.lambda_exec_shared.name
  policy_arn = aws_iam_policy.dynamo_crud_policy.arn
}
# ----------------------------------- END Database set up (DYNAMODB) -----------------------------------


# ----------------------------------- START set up (API GATEWAY) -----------------------------------
resource "aws_api_gateway_rest_api" "users_api" {
  name        = "UsersCRUD-API"
  description = "API para HaroldSoftware con proteccion CORS y Throttling"
}

resource "aws_api_gateway_resource" "users_resource" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  parent_id   = aws_api_gateway_rest_api.users_api.root_resource_id
  path_part   = "users"
}

# Metodo ANY (Proxy para la Lambda)
resource "aws_api_gateway_method" "users_method" {
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.users_resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.users_api.id
  resource_id             = aws_api_gateway_resource.users_resource.id
  http_method             = aws_api_gateway_method.users_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.lambda_producer_name}/invocations"
}

# --- 4. CONFIGURACIÓN DE CORS (OPTIONS) ---
resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.users_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.users_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.users_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.users_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'https://haroldsoftware.com'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
  }
  depends_on = [aws_api_gateway_integration.options_integration]
}
# ----------------------------------- END set up (API GATEWAY) -----------------------------------


# ----------------------------------- START set up (THROTTLING) -----------------------------------
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.users_resource.id,
      aws_api_gateway_method.users_method.http_method,
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_method.options_method.http_method,
      aws_api_gateway_integration.options_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.lambda_integration, 
    aws_api_gateway_integration.options_integration
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  stage_name    = "prod"
}

resource "aws_api_gateway_method_settings" "throttling" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}
# ----------------------------------- END set up (THROTTLING) -----------------------------------


# ----------------------------------- START set up (SQS) -----------------------------------
resource "aws_sqs_queue" "user_creation_queue" {
  name                      = "user-creation-queue"
  message_retention_seconds = 86400 # 1 día
  receive_wait_time_seconds = 10    # Long polling
}

# --- 2. PERMISOS ADICIONALES PARA EL ROL COMPARTIDO ---
resource "aws_iam_policy" "sqs_policy" {
  name = "LambdaSQSPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Effect   = "Allow"
        Resource = aws_sqs_queue.user_creation_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sqs_attach" {
  role       = aws_iam_role.lambda_exec_shared.name
  policy_arn = aws_iam_policy.sqs_policy.arn
}

# --- OUTPUT PARA LA URL DE LA COLA ---
output "sqs_url" {
  value = aws_sqs_queue.user_creation_queue.id
}
# ----------------------------------- END set up (SQS) -----------------------------------
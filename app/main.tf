# ... (terraform y providers se mantienen igual) ...

# --- DATA SOURCES ---
data "aws_iam_role" "shared_role" { name = "go_lambda_execution_role_shared" }
data "aws_sqs_queue" "user_queue" { name = "user-creation-queue" }

# --- EMPAQUETADO ---
data "archive_file" "api_zip" {
  type        = "zip"
  source_file = "../bootstrap_api"
  output_path = "api_producer.zip"
}

data "archive_file" "worker_zip" {
  type        = "zip"
  source_file = "../bootstrap_worker"
  output_path = "worker_processor.zip"
}

# ---------------------------------------------- SSM SECRET GRATUITO  ----------------------------------------------
# 1. Crear el parámetro seguro (Gratis)
resource "aws_ssm_parameter" "mongo_db_uri" {
  name        = "/prod/mongodb/uri"
  description = "URI de conexion para MongoDB Atlas"
  type        = "SecureString"
  value       = "placeholder_cambiar_manualmente" # El valor real lo pones por CLI o Consola

  lifecycle {
    ignore_changes = [value] # Evita que Terraform sobrescriba el valor real con el placeholder
  }
}

# 2. Ajustar la política de IAM para SSM
resource "aws_iam_policy" "ssm_policy" {
  name = "LambdaSSMReadPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "ssm:GetParameter"
      Effect   = "Allow"
      Resource = aws_ssm_parameter.mongo_db_uri.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.lambda_exec_shared.name
  policy_arn = aws_iam_policy.ssm_policy.arn
}
# ---------------------------------------------- SSM SECRET GRATUITO  ----------------------------------------------


# --- LAMBDAS ---

# 1. Producer API
resource "aws_lambda_function" "api_producer" {
  function_name    = var.lambda_producer_name
  filename         = data.archive_file.api_zip.output_path
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  handler          = "bootstrap"
  runtime          = "provided.al2023"
  role             = data.aws_iam_role.shared_role.arn
  architectures    = ["arm64"]

  environment {
    variables = {
      TABLE_NAME = "UsersTable"
      SQS_URL    = data.aws_sqs_queue.user_queue.id
    }
  }
}

# 2. Worker SQS
resource "aws_lambda_function" "sqs_worker" {
  function_name    = var.lambda_worker_name # Usar variable
  filename         = data.archive_file.worker_zip.output_path
  source_code_hash = data.archive_file.worker_zip.output_base64sha256
  handler          = "bootstrap"
  runtime          = "provided.al2023"
  role             = data.aws_iam_role.shared_role.arn
  architectures    = ["arm64"]
  reserved_concurrent_executions = 1

  environment {
    variables = {
      TABLE_NAME = "UsersTable"
      MONGO_URI = var.mongo_param_path
    }
  }
}

# --- TRIGGERS ---
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = data.aws_sqs_queue.user_queue.arn
  function_name    = aws_lambda_function.sqs_worker.arn
  batch_size       = 1
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.aws_account_id}:*/*/*"
}
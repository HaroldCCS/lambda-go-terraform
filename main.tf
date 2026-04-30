provider "aws" {
  region = "us-east-1" # Cambia según tu preferencia
}

# Rol de IAM para la Lambda
resource "aws_iam_role" "iam_for_lambda" {
  name = "my_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# Política básica para logs en CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Definición de la función Lambda
resource "aws_lambda_function" "test_lambda" {
  filename      = "deployment.zip"
  function_name = "my_go_lambda"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "bootstrap" # Requerido para runtime provided.al2023

  runtime = "provided.al2023"
  architectures = ["x86_64"]
}
variable "lambda_producer_name" {
  default = "users-api-producer"
}

variable "lambda_worker_name" {
  default = "user-sqs-worker"
}

variable "mongo_param_path" {
  default = "/prod/mongodb/uri"
}

variable "mongo_uri_value" {
  description = "El valor real de la URI de MongoDB"
  type        = string
  sensitive   = true
}

variable "aws_account_id" {
  default = "638630172726"
}

variable "aws_region" {
  default = "us-east-1"
}
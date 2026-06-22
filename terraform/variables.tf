# terraform/variables.tf

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "s3_bucket_name" {
  description = "Name of S3 bucket for logs (must be globally unique)"
  type        = string

  validation {
    condition     = length(var.s3_bucket_name) >= 3 && length(var.s3_bucket_name) <= 63
    error_message = "Bucket name must be between 3 and 63 characters."
  }
}

variable "iam_user_name" {
  description = "Name of IAM user for Cloudflare Worker"
  type        = string
  default     = "clicky-worker"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.iam_user_name))
    error_message = "IAM user name can only contain alphanumeric characters and hyphens."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 14

  validation {
    condition     = var.log_retention_days > 0
    error_message = "Log retention days must be greater than 0."
  }
}

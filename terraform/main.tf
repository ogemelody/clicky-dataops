# terraform/main.tf

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to use remote state (optional)
  # backend "s3" {
  #   bucket         = "clicky-terraform-state"
  #   key            = "clicky-analytics/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "clicky-analytics"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedAt   = timestamp()
    }
  }
}

# ============================================================================
# S3 BUCKET FOR LOGS
# ============================================================================

resource "aws_s3_bucket" "clicky_logs" {
  bucket = var.s3_bucket_name

  tags = {
    Name = "Clicky Analytics Logs"
  }
}

# Enable versioning (for safety)
resource "aws_s3_bucket_versioning" "clicky_logs" {
  bucket = aws_s3_bucket.clicky_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block public access (security)
resource "aws_s3_bucket_public_access_block" "clicky_logs" {
  bucket = aws_s3_bucket.clicky_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "clicky_logs" {
  bucket = aws_s3_bucket.clicky_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle policy (archive old logs)
resource "aws_s3_bucket_lifecycle_configuration" "clicky_logs" {
  bucket = aws_s3_bucket.clicky_logs.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# ============================================================================
# IAM USER FOR CLOUDFLARE WORKER
# ============================================================================

resource "aws_iam_user" "clicky_worker" {
  name = var.iam_user_name

  tags = {
    Description = "User for Cloudflare Worker to access S3"
  }
}

# Access keys for the user
resource "aws_iam_access_key" "clicky_worker" {
  user = aws_iam_user.clicky_worker.name
}

# ============================================================================
# IAM POLICY FOR S3 ACCESS
# ============================================================================

resource "aws_iam_policy" "s3_access" {
  name        = "clicky-s3-access"
  description = "Policy for Clicky Worker to read/write to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.clicky_logs.arn,
          "${aws_s3_bucket.clicky_logs.arn}/*"
        ]
      }
    ]
  })
}

# Attach policy to user
resource "aws_iam_user_policy_attachment" "worker_s3_access" {
  user       = aws_iam_user.clicky_worker.name
  policy_arn = aws_iam_policy.s3_access.arn
}

# ============================================================================
# IAM POLICY FOR VERCEL APP (READ-ONLY ACCESS)
# ============================================================================

resource "aws_iam_policy" "s3_read_only" {
  name        = "clicky-s3-read-only"
  description = "Policy for Vercel app to read logs from S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadOnly"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.clicky_logs.arn,
          "${aws_s3_bucket.clicky_logs.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user" "vercel_app" {
  name = "${var.iam_user_name}-vercel"

  tags = {
    Description = "User for Vercel app to read S3 logs"
  }
}

resource "aws_iam_access_key" "vercel_app" {
  user = aws_iam_user.vercel_app.name
}

resource "aws_iam_user_policy_attachment" "vercel_s3_read" {
  user       = aws_iam_user.vercel_app.name
  policy_arn = aws_iam_policy.s3_read_only.arn
}

# ============================================================================
# CLOUDWATCH LOG GROUP (optional, for monitoring)
# ============================================================================

resource "aws_cloudwatch_log_group" "clicky_worker" {
  name              = "/clicky/worker"
  retention_in_days = 14

  tags = {
    Description = "Logs for Clicky Worker"
  }
}

# ============================================================================
# OUTPUTS (for use in Cloudflare + Vercel)
# ============================================================================

output "s3_bucket_name" {
  value       = aws_s3_bucket.clicky_logs.id
  description = "S3 bucket name for logs"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.clicky_logs.arn
  description = "S3 bucket ARN"
}

output "worker_access_key_id" {
  value       = aws_iam_access_key.clicky_worker.id
  description = "Access Key ID for Cloudflare Worker"
  sensitive   = true
}

output "worker_secret_access_key" {
  value       = aws_iam_access_key.clicky_worker.secret
  description = "Secret Access Key for Cloudflare Worker"
  sensitive   = true
}

output "vercel_access_key_id" {
  value       = aws_iam_access_key.vercel_app.id
  description = "Access Key ID for Vercel App"
  sensitive   = true
}

output "vercel_secret_access_key" {
  value       = aws_iam_access_key.vercel_app.secret
  description = "Secret Access Key for Vercel App"
  sensitive   = true
}

output "cloudwatch_log_group" {
  value       = aws_cloudwatch_log_group.clicky_worker.name
  description = "CloudWatch log group name"
}

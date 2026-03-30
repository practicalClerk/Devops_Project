# Lambda Function for Serverless Predictions
resource "aws_lambda_function" "predictor" {
  function_name = "${local.name_prefix}-predictor"
  description    = "Serverless CI/CD failure prediction"
  role           = aws_iam_role.lambda_role.arn
  package_type   = "Zip"
  runtime        = "python3.11"
  handler        = "lambda_handler.lambda_handler"
  timeout        = 30
  memory_size    = 512

  s3_bucket = aws_s3_bucket.lambda_artifacts.id
  s3_key    = aws_s3_object.lambda_code.key

  environment {
    variables = {
      S3_MODEL_BUCKET = aws_s3_bucket.models.id
      S3_MODEL_PREFIX = "models"
      LOG_LEVEL       = "INFO"
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_cloudwatch_log_group.lambda
  ]
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Lambda IAM Policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-predictor*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.models.arn}/*"
      }
    ]
  })
}

# Lambda CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-predictor"
  retention_in_days = 7

  tags = local.common_tags
}

# Lambda URL for direct HTTP access
resource "aws_lambda_function_url" "predictor" {
  function_name              = aws_lambda_function.predictor.function_name
  authorization_type         = "NONE"
  invoke_mode               = "RESPONSE_STREAM"

  cors {
    allow_headers = ["*"]
    allow_methods = ["POST", "GET"]
    allow_origins = ["*"]
  }
}

# API Gateway for Lambda (alternative to Lambda URL)
resource "aws_apigatewayv2_api" "predictor" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "API Gateway for ML CI/CD Predictor Lambda"

  tags = local.common_tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.predictor.id
  name        = "$default"
  auto_deploy = true

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "predictor" {
  api_id           = aws_apigatewayv2_api.predictor.id
  integration_type = "AWS_PROXY"

  connection_type           = "INTERNET"
  description              = "Lambda integration"
  integration_uri          = aws_lambda_function.predictor.arn
  payload_format_version   = "2.0"

  timeout_milliseconds = 30000
}

resource "aws_apigatewayv2_route" "predict" {
  api_id    = aws_apigatewayv2_api.predictor.id
  route_key = "POST /predict"

  target = "integrations/${aws_apigatewayv2_integration.predictor.id}"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.predictor.id
  route_key = "GET /health"

  target = "integrations/${aws_apigatewayv2_integration.predictor.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.predictor.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.predictor.execution_arn}/*/*"
}

# S3 Bucket for Lambda Code
resource "aws_s3_bucket" "lambda_artifacts" {
  bucket_prefix = "${local.name_prefix}-lambda-"

  tags = merge(local.common_tags, {
    Purpose = "lambda-code-storage"
  })
}

resource "aws_s3_bucket_versioning" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "lambda_code" {
  bucket  = aws_s3_bucket.lambda_artifacts.id
  key     = "lambda/predictor.zip"
  source  = "./lambda/predictor.zip"

  # This should be updated after building the Lambda package
  etag    = filemd5("./lambda/predictor.zip")
}

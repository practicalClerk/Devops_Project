# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

# ECS Outputs
output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.app.arn
}

# ECR Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.app.name
}

# ALB Outputs
output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = var.enable_alb ? aws_lb.app[0].dns_name : null
}

output "alb_zone_id" {
  description = "Zone ID of the load balancer"
  value       = var.enable_alb ? aws_lb.app[0].zone_id : null
}

output "alb_arn" {
  description = "ARN of the load balancer"
  value       = var.enable_alb ? aws_lb.app[0].arn : null
}

# Security Group Outputs
output "ecs_security_group_id" {
  description = "ID of the ECS security group"
  value       = aws_security_group.ecs.id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = var.enable_alb ? aws_security_group.alb[0].id : null
}

# Other Outputs
output "cloudwatch_log_group" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret for Groq API key"
  value       = aws_secretsmanager_secret.groq_key.arn
}

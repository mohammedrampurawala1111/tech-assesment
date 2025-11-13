output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "cluster_id" {
  description = "ECS Cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "ECS Cluster Name"
  value       = aws_ecs_cluster.main.name
}

output "alb_dns_name" {
  description = "ALB DNS Name"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "target_group_arn" {
  description = "Blue Target Group ARN"
  value       = aws_lb_target_group.blue.arn
}

output "blue_target_group_arn" {
  description = "Blue Target Group ARN"
  value       = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  description = "Green Target Group ARN"
  value       = aws_lb_target_group.green.arn
}

output "codedeploy_app_name" {
  description = "CodeDeploy Application Name"
  value       = aws_codedeploy_app.ecs.name
}

output "codedeploy_deployment_group_name" {
  description = "CodeDeploy Deployment Group Name"
  value       = aws_codedeploy_deployment_group.ecs.deployment_group_name
}

output "task_definition_family" {
  description = "Task Definition Family (for deployments)"
  value       = "${var.project_name}-app"
}

output "service_name" {
  description = "ECS Service Name"
  value       = aws_ecs_service.main.name
}

output "listener_arn" {
  description = "ALB Listener ARN"
  value       = aws_lb_listener.main.arn
}

output "private_subnet_ids" {
  description = "Private Subnet IDs"
  value       = aws_subnet.private[*].id
}

output "ecs_task_security_group_id" {
  description = "ECS Task Security Group ID"
  value       = aws_security_group.ecs_tasks.id
}

output "aws_region" {
  description = "AWS Region"
  value       = var.aws_region
}

output "alb_arn_suffix" {
  description = "ALB ARN Suffix (for CloudWatch metrics)"
  value       = aws_lb.main.arn_suffix
}

output "alb_success_rate_alarm_name" {
  description = "CloudWatch alarm name for ALB success rate"
  value       = aws_cloudwatch_metric_alarm.alb_success_rate.alarm_name
}

output "container_name" {
  description = "Container name for AppSpec"
  value       = "${var.project_name}-app"
}

output "container_port" {
  description = "Container port for AppSpec"
  value       = var.container_port
}

output "ecs_task_execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ECS Task Role ARN"
  value       = aws_iam_role.ecs_task.arn
}

output "ecs_log_group" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.ecs.name
}


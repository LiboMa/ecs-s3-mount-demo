output "s3_bucket_name" {
  description = "S3存储桶名称"
  value       = aws_s3_bucket.test_bucket.bucket
}

output "ecs_cluster_name" {
  description = "ECS集群名称"
  value       = aws_ecs_cluster.main.name
}

output "app_service_name" {
  description = "应用服务名称"
  value       = aws_ecs_service.app_service.name
}



output "load_balancer_dns" {
  description = "负载均衡器DNS名称"
  value       = aws_lb.main.dns_name
}

output "app_url" {
  description = "应用访问URL"
  value       = "http://${aws_lb.main.dns_name}"
}

output "task_role_arn" {
  description = "ECS任务角色ARN"
  value       = aws_iam_role.ecs_task_role.arn
}
variable "project_name" {
  description = "项目名称"
  type        = string
  default     = "ecs-s3-test"
}

variable "aws_region" {
  description = "AWS区域"
  type        = string
  default     = "us-west-2"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "子网ID列表"
  type        = list(string)
}

variable "app_ecr_repository_url" {
  description = "ECR仓库URL (Mountpoint-S3 API应用)"
  type        = string
}
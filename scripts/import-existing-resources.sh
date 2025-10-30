#!/bin/bash

set -e

echo "=== 导入现有AWS资源到Terraform状态 ==="

cd terraform

# 检查terraform.tfvars是否存在
if [ ! -f "terraform.tfvars" ]; then
    echo "❌ terraform.tfvars文件不存在"
    echo "请先运行 ./scripts/regenerate-tfvars.sh"
    exit 1
fi

# 读取项目名称
PROJECT_NAME=$(grep 'project_name' terraform.tfvars | cut -d'"' -f2)
AWS_REGION=$(grep 'aws_region' terraform.tfvars | cut -d'"' -f2)

echo "项目名称: $PROJECT_NAME"
echo "AWS区域: $AWS_REGION"
echo ""

# 函数：检查资源是否已在Terraform状态中
resource_exists_in_state() {
    local resource_address="$1"
    terraform state show "$resource_address" &>/dev/null
}

# 函数：导入资源
import_resource() {
    local resource_address="$1"
    local resource_id="$2"
    local resource_name="$3"
    
    if resource_exists_in_state "$resource_address"; then
        echo "✅ $resource_name 已在Terraform状态中"
    else
        echo "🔄 导入 $resource_name..."
        if terraform import "$resource_address" "$resource_id" 2>/dev/null; then
            echo "✅ $resource_name 导入成功"
        else
            echo "⚠️  $resource_name 导入失败或不存在，将创建新资源"
        fi
    fi
}

echo "开始导入现有资源..."
echo ""

# 1. 导入CloudWatch日志组
echo "1. 检查CloudWatch日志组..."
import_resource "aws_cloudwatch_log_group.ecs_logs" "/ecs/$PROJECT_NAME" "CloudWatch日志组"

# 2. 导入IAM角色
echo ""
echo "2. 检查IAM角色..."
import_resource "aws_iam_role.ecs_task_execution_role" "$PROJECT_NAME-ecs-task-execution-role" "ECS任务执行角色"
import_resource "aws_iam_role.ecs_task_role" "$PROJECT_NAME-ecs-task-role" "ECS任务角色"

# 3. 导入负载均衡器
echo ""
echo "3. 检查负载均衡器..."
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$PROJECT_NAME-alb" --region "$AWS_REGION" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "None")
if [ "$ALB_ARN" != "None" ] && [ "$ALB_ARN" != "null" ]; then
    import_resource "aws_lb.main" "$ALB_ARN" "应用负载均衡器"
fi

# 4. 导入目标组
echo ""
echo "4. 检查目标组..."
TG_ARN=$(aws elbv2 describe-target-groups --names "$PROJECT_NAME-app-tg" --region "$AWS_REGION" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "None")
if [ "$TG_ARN" != "None" ] && [ "$TG_ARN" != "null" ]; then
    import_resource "aws_lb_target_group.app" "$TG_ARN" "目标组"
fi

# 5. 导入ECS集群
echo ""
echo "5. 检查ECS集群..."
CLUSTER_ARN=$(aws ecs describe-clusters --clusters "$PROJECT_NAME-cluster" --region "$AWS_REGION" --query 'clusters[0].clusterArn' --output text 2>/dev/null || echo "None")
if [ "$CLUSTER_ARN" != "None" ] && [ "$CLUSTER_ARN" != "null" ]; then
    import_resource "aws_ecs_cluster.main" "$PROJECT_NAME-cluster" "ECS集群"
fi

echo ""
echo "导入完成！现在运行terraform plan检查状态..."
echo ""

if terraform plan -detailed-exitcode; then
    echo ""
    echo "✅ 所有资源状态同步完成！"
else
    exit_code=$?
    if [ $exit_code -eq 2 ]; then
        echo ""
        echo "📋 发现需要应用的更改，运行以下命令应用："
        echo "  cd terraform && terraform apply"
    else
        echo ""
        echo "❌ Terraform plan失败"
        exit 1
    fi
fi

cd ..
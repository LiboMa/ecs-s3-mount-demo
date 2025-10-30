#!/bin/bash

set -e

echo "=== ECS S3挂载测试项目部署脚本 ==="

# 检查环境文件
if [ ! -f .env ]; then
    echo "❌ 未找到.env文件，请先运行 ./scripts/setup.sh"
    exit 1
fi

source .env

# 部署基础设施
deploy_infrastructure() {
    echo "部署基础设施..."
    
    cd terraform
    
    # 检查是否已初始化
    if [ ! -d ".terraform" ]; then
        echo "初始化Terraform..."
        terraform init;

        if ! terraform init; then
            echo "❌ Terraform初始化失败"
            cd ..
            exit 1
        fi
    else
        echo "✅ Terraform已初始化"
    fi
    
    # 验证配置文件
    echo "验证Terraform配置..."
    if ! terraform validate; then
        echo "❌ Terraform配置验证失败"
        cd ..
        exit 1
    fi
    
    # 规划部署
    echo "生成部署计划..."
    terraform plan
    
    # 确认部署
    echo ""
    read -p "是否继续部署？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "部署已取消"
        exit 1
    fi
    
    # 执行部署
    if ! terraform apply -auto-approve; then
        echo "❌ Terraform部署失败，可能存在资源冲突"
        echo "尝试处理已存在的资源..."
        cd ..
        ./scripts/handle-existing-resources.sh
        exit 1
    fi
    
    # 获取输出
    S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
    ECS_CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
    ECS_SERVICE_NAME=$(terraform output -raw app_service_name)
    
    cd ..
    
    # 更新环境文件
    echo "S3_BUCKET_NAME=$S3_BUCKET_NAME" >> .env
    echo "ECS_CLUSTER_NAME=$ECS_CLUSTER_NAME" >> .env
    echo "ECS_SERVICE_NAME=$ECS_SERVICE_NAME" >> .env
    
    echo "✅ 基础设施部署成功"
    echo "  S3存储桶: $S3_BUCKET_NAME"
    echo "  ECS集群: $ECS_CLUSTER_NAME"
    echo "  ECS服务: $ECS_SERVICE_NAME"
}

# 上传测试数据到S3
upload_test_data() {
    echo "上传测试数据到S3..."
    
    if [ -d temp_test_data ]; then
        aws s3 sync temp_test_data/ s3://$S3_BUCKET_NAME/test_data/ --region $AWS_REGION
        echo "✅ 测试数据上传完成"
    else
        echo "⚠️  未找到测试数据目录，跳过上传"
    fi
}

# 等待ECS服务启动
wait_for_service() {
    echo "等待ECS服务启动..."
    
    aws ecs wait services-stable \
        --cluster $ECS_CLUSTER_NAME \
        --services $ECS_SERVICE_NAME \
        --region $AWS_REGION
    
    echo "✅ ECS服务启动完成"
}

# 检查服务状态
check_service_status() {
    echo "检查服务状态..."
    
    # 获取任务ARN
    TASK_ARN=$(aws ecs list-tasks \
        --cluster $ECS_CLUSTER_NAME \
        --service-name $ECS_SERVICE_NAME \
        --region $AWS_REGION \
        --query 'taskArns[0]' \
        --output text)
    
    if [ "$TASK_ARN" = "None" ] || [ -z "$TASK_ARN" ]; then
        echo "❌ 未找到运行中的任务"
        return 1
    fi
    
    # 获取任务详情
    aws ecs describe-tasks \
        --cluster $ECS_CLUSTER_NAME \
        --tasks $TASK_ARN \
        --region $AWS_REGION \
        --query 'tasks[0].{Status:lastStatus,Health:healthStatus,CreatedAt:createdAt}' \
        --output table
    
    echo "任务ARN: $TASK_ARN"
    echo "TASK_ARN=$TASK_ARN" >> .env
}

# 查看日志
show_logs() {
    echo "获取最新日志..."
    
    LOG_GROUP="/ecs/ecs-s3-test"
    
    # 获取最新的日志流
    LOG_STREAM=$(aws logs describe-log-streams \
        --log-group-name $LOG_GROUP \
        --region $AWS_REGION \
        --order-by LastEventTime \
        --descending \
        --max-items 1 \
        --query 'logStreams[0].logStreamName' \
        --output text)
    
    if [ "$LOG_STREAM" != "None" ] && [ -n "$LOG_STREAM" ]; then
        echo "最新日志 (日志流: $LOG_STREAM):"
        aws logs get-log-events \
            --log-group-name $LOG_GROUP \
            --log-stream-name $LOG_STREAM \
            --region $AWS_REGION \
            --query 'events[].message' \
            --output text | tail -20
    else
        echo "⚠️  未找到日志流"
    fi
}

# 主函数
main() {
    echo "开始部署ECS S3挂载测试项目..."
    
    deploy_infrastructure
    upload_test_data
    wait_for_service
    check_service_status
    show_logs
    
    echo ""
    echo "🎉 部署完成！"
    echo ""
    echo "下一步操作："
    echo "1. 运行 './scripts/test.sh' 执行测试"
    echo "2. 运行 './scripts/logs.sh' 查看详细日志"
    echo "3. 运行 './scripts/cleanup.sh' 清理资源"
}

main "$@"
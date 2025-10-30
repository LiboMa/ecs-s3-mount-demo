#!/bin/bash

set -e

echo "=== ECS S3挂载测试执行脚本 ==="

# 检查环境文件
if [ ! -f .env ]; then
    echo "❌ 未找到.env文件，请先运行部署脚本"
    exit 1
fi

source .env

# 运行测试任务
run_test_task() {
    echo "启动测试任务..."
    
    # 获取任务定义ARN
    TASK_DEFINITION_ARN=$(aws ecs describe-task-definition \
        --task-definition ecs-s3-test-s3-test \
        --region $AWS_REGION \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    # 获取子网和安全组
    SUBNET_ID=$(echo $SUBNET_IDS | jq -r '.[0]')
    SECURITY_GROUP=$(aws ecs describe-services \
        --cluster $ECS_CLUSTER_NAME \
        --services $ECS_SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' \
        --output text)
    
    # 运行测试任务
    TEST_TASK_ARN=$(aws ecs run-task \
        --cluster $ECS_CLUSTER_NAME \
        --task-definition $TASK_DEFINITION_ARN \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}" \
        --overrides '{
            "containerOverrides": [{
                "name": "s3-test-container",
                "environment": [
                    {"name": "RUN_MODE", "value": "test"},
                    {"name": "S3_BUCKET_NAME", "value": "'$S3_BUCKET_NAME'"},
                    {"name": "AWS_REGION", "value": "'$AWS_REGION'"}
                ]
            }]
        }' \
        --region $AWS_REGION \
        --query 'tasks[0].taskArn' \
        --output text)
    
    echo "✅ 测试任务已启动"
    echo "任务ARN: $TEST_TASK_ARN"
    
    return 0
}

# 等待测试完成
wait_for_test_completion() {
    echo "等待测试完成..."
    
    local task_arn=$1
    local max_wait=600  # 10分钟超时
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        TASK_STATUS=$(aws ecs describe-tasks \
            --cluster $ECS_CLUSTER_NAME \
            --tasks $task_arn \
            --region $AWS_REGION \
            --query 'tasks[0].lastStatus' \
            --output text)
        
        echo "当前状态: $TASK_STATUS (等待时间: ${wait_time}s)"
        
        if [ "$TASK_STATUS" = "STOPPED" ]; then
            # 获取退出代码
            EXIT_CODE=$(aws ecs describe-tasks \
                --cluster $ECS_CLUSTER_NAME \
                --tasks $task_arn \
                --region $AWS_REGION \
                --query 'tasks[0].containers[0].exitCode' \
                --output text)
            
            echo "✅ 测试任务完成，退出代码: $EXIT_CODE"
            return $EXIT_CODE
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    echo "❌ 测试任务超时"
    return 1
}

# 获取测试日志
get_test_logs() {
    echo "获取测试日志..."
    
    local task_arn=$1
    
    # 提取任务ID
    TASK_ID=$(echo $task_arn | cut -d'/' -f3)
    
    LOG_GROUP="/ecs/ecs-s3-test"
    LOG_STREAM="ecs/s3-test-container/$TASK_ID"
    
    echo "日志组: $LOG_GROUP"
    echo "日志流: $LOG_STREAM"
    
    # 等待日志流创建
    sleep 5
    
    # 获取日志
    aws logs get-log-events \
        --log-group-name $LOG_GROUP \
        --log-stream-name $LOG_STREAM \
        --region $AWS_REGION \
        --query 'events[].message' \
        --output text 2>/dev/null || echo "⚠️  暂时无法获取日志，请稍后查看"
}

# 运行交互式测试
run_interactive_test() {
    echo "启动交互式测试容器..."
    
    # 获取任务定义ARN
    TASK_DEFINITION_ARN=$(aws ecs describe-task-definition \
        --task-definition ecs-s3-test-s3-test \
        --region $AWS_REGION \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    # 获取子网和安全组
    SUBNET_ID=$(echo $SUBNET_IDS | jq -r '.[0]')
    SECURITY_GROUP=$(aws ecs describe-services \
        --cluster $ECS_CLUSTER_NAME \
        --services $ECS_SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' \
        --output text)
    
    # 运行交互式任务
    INTERACTIVE_TASK_ARN=$(aws ecs run-task \
        --cluster $ECS_CLUSTER_NAME \
        --task-definition $TASK_DEFINITION_ARN \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}" \
        --overrides '{
            "containerOverrides": [{
                "name": "s3-test-container",
                "environment": [
                    {"name": "RUN_MODE", "value": "interactive"},
                    {"name": "S3_BUCKET_NAME", "value": "'$S3_BUCKET_NAME'"},
                    {"name": "AWS_REGION", "value": "'$AWS_REGION'"}
                ]
            }]
        }' \
        --region $AWS_REGION \
        --query 'tasks[0].taskArn' \
        --output text)
    
    echo "✅ 交互式任务已启动"
    echo "任务ARN: $INTERACTIVE_TASK_ARN"
    echo ""
    echo "使用以下命令连接到容器："
    echo "aws ecs execute-command \\"
    echo "  --cluster $ECS_CLUSTER_NAME \\"
    echo "  --task $INTERACTIVE_TASK_ARN \\"
    echo "  --container s3-test-container \\"
    echo "  --interactive \\"
    echo "  --command '/bin/bash'"
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -t, --test        运行自动化测试 (默认)"
    echo "  -i, --interactive 启动交互式测试容器"
    echo "  -l, --logs        仅查看最新日志"
    echo "  -h, --help        显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                # 运行自动化测试"
    echo "  $0 --interactive  # 启动交互式容器"
    echo "  $0 --logs         # 查看日志"
}

# 主函数
main() {
    local mode="test"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--test)
                mode="test"
                shift
                ;;
            -i|--interactive)
                mode="interactive"
                shift
                ;;
            -l|--logs)
                mode="logs"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    case $mode in
        "test")
            echo "开始执行自动化测试..."
            task_arn=$(run_test_task)
            wait_for_test_completion $task_arn
            exit_code=$?
            get_test_logs $task_arn
            
            if [ $exit_code -eq 0 ]; then
                echo "🎉 测试执行成功！"
            else
                echo "❌ 测试执行失败，退出代码: $exit_code"
            fi
            exit $exit_code
            ;;
        "interactive")
            run_interactive_test
            ;;
        "logs")
            if [ -n "$TASK_ARN" ]; then
                get_test_logs $TASK_ARN
            else
                echo "❌ 未找到任务ARN，请先运行测试"
                exit 1
            fi
            ;;
    esac
}

main "$@"
#!/bin/bash

set -e

echo "=== ECS S3挂载测试项目清理脚本 ==="

# 检查环境文件
if [ ! -f .env ]; then
    echo "❌ 未找到.env文件"
    exit 1
fi

source .env

# 确认清理操作
confirm_cleanup() {
    echo "⚠️  警告: 此操作将删除以下资源:"
    echo "  - ECS集群和服务"
    echo "  - S3存储桶及其内容"
    echo "  - IAM角色和策略"
    echo "  - CloudWatch日志组"
    echo "  - ECR仓库"
    echo ""
    read -p "确定要继续吗？(输入 'yes' 确认): " -r
    if [[ ! $REPLY == "yes" ]]; then
        echo "清理操作已取消"
        exit 0
    fi
}

# 停止ECS服务
stop_ecs_service() {
    echo "停止ECS服务..."
    
    if [ -n "$ECS_CLUSTER_NAME" ] && [ -n "$ECS_SERVICE_NAME" ]; then
        # 将服务期望数量设为0
        aws ecs update-service \
            --cluster $ECS_CLUSTER_NAME \
            --service $ECS_SERVICE_NAME \
            --desired-count 0 \
            --region $AWS_REGION \
            > /dev/null 2>&1 || echo "⚠️  ECS服务可能已经停止"
        
        echo "✅ ECS服务停止请求已发送"
    else
        echo "⚠️  未找到ECS服务信息，跳过"
    fi
}

# 清空S3存储桶
empty_s3_bucket() {
    echo "清空S3存储桶..."
    
    if [ -n "$S3_BUCKET_NAME" ]; then
        # 删除所有对象版本
        aws s3api list-object-versions \
            --bucket $S3_BUCKET_NAME \
            --region $AWS_REGION \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object \
                    --bucket $S3_BUCKET_NAME \
                    --key "$key" \
                    --version-id "$version" \
                    --region $AWS_REGION > /dev/null
            fi
        done
        
        # 删除删除标记
        aws s3api list-object-versions \
            --bucket $S3_BUCKET_NAME \
            --region $AWS_REGION \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object \
                    --bucket $S3_BUCKET_NAME \
                    --key "$key" \
                    --version-id "$version" \
                    --region $AWS_REGION > /dev/null
            fi
        done
        
        echo "✅ S3存储桶已清空"
    else
        echo "⚠️  未找到S3存储桶信息，跳过"
    fi
}

# 销毁Terraform资源
destroy_terraform() {
    echo "销毁Terraform资源..."
    
    cd terraform
    
    if [ -f terraform.tfstate ]; then
        terraform destroy -auto-approve
        echo "✅ Terraform资源销毁完成"
    else
        echo "⚠️  未找到Terraform状态文件，跳过"
    fi
    
    cd ..
}

# 删除ECR仓库
delete_ecr_repository() {
    echo "删除ECR仓库..."
    
    REPO_NAME="ecs-s3-test"
    
    if aws ecr describe-repositories --repository-names $REPO_NAME --region $AWS_REGION &> /dev/null; then
        aws ecr delete-repository \
            --repository-name $REPO_NAME \
            --force \
            --region $AWS_REGION
        echo "✅ ECR仓库删除完成"
    else
        echo "⚠️  ECR仓库不存在，跳过"
    fi
}

# 清理本地文件
cleanup_local_files() {
    echo "清理本地文件..."
    
    # 删除临时文件
    rm -rf temp_test_data/
    rm -f .env
    rm -f terraform/terraform.tfvars
    rm -f terraform/terraform.tfstate*
    rm -rf terraform/.terraform/
    
    echo "✅ 本地文件清理完成"
}

# 清理Docker镜像
cleanup_docker_images() {
    echo "清理Docker镜像..."
    
    # 删除本地镜像
    docker rmi ecs-s3-test:latest 2>/dev/null || echo "⚠️  本地镜像不存在"
    
    if [ -n "$ECR_REPOSITORY_URL" ]; then
        docker rmi $ECR_REPOSITORY_URL:latest 2>/dev/null || echo "⚠️  ECR镜像标签不存在"
    fi
    
    echo "✅ Docker镜像清理完成"
}

# 显示清理摘要
show_cleanup_summary() {
    echo ""
    echo "🧹 清理完成摘要:"
    echo "  ✅ ECS服务已停止"
    echo "  ✅ S3存储桶已清空并删除"
    echo "  ✅ IAM角色和策略已删除"
    echo "  ✅ CloudWatch日志组已删除"
    echo "  ✅ ECR仓库已删除"
    echo "  ✅ 本地文件已清理"
    echo "  ✅ Docker镜像已清理"
    echo ""
    echo "所有资源已成功清理！"
}

# 主函数
main() {
    echo "开始清理ECS S3挂载测试项目资源..."
    
    confirm_cleanup
    stop_ecs_service
    empty_s3_bucket
    destroy_terraform
    delete_ecr_repository
    cleanup_local_files
    cleanup_docker_images
    show_cleanup_summary
}

main "$@"
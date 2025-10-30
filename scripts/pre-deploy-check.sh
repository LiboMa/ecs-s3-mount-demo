#!/bin/bash

set -e

echo "=== 部署前检查脚本 ==="

# 检查必要文件
check_required_files() {
    echo "1. 检查必要文件..."
    
    local required_files=(
        ".env"
        "terraform/terraform.tfvars"
        "terraform/main.tf"
        "terraform/variables.tf"
        "terraform/ecs.tf"
        "terraform/outputs.tf"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            echo "✅ $file 存在"
        else
            echo "❌ $file 不存在"
            return 1
        fi
    done
}

# 检查环境变量
check_environment_variables() {
    echo "2. 检查环境变量..."
    
    if [ -f .env ]; then
        source .env
        
        local required_vars=(
            "APP_ECR_REPOSITORY_URL"
            "AWS_REGION"
            "VPC_ID"
            "SUBNET_IDS"
        )
        
        for var in "${required_vars[@]}"; do
            if [ -n "${!var}" ]; then
                echo "✅ $var 已设置"
            else
                echo "❌ $var 未设置"
                return 1
            fi
        done
    else
        echo "❌ .env文件不存在"
        return 1
    fi
}

# 检查AWS凭证
check_aws_credentials() {
    echo "3. 检查AWS凭证..."
    
    if aws sts get-caller-identity &> /dev/null; then
        echo "✅ AWS凭证有效"
        aws sts get-caller-identity --query 'Account' --output text | xargs echo "账户ID:"
    else
        echo "❌ AWS凭证无效或未配置"
        return 1
    fi
}

# 检查Docker镜像
check_docker_images() {
    echo "4. 检查Docker镜像..."
    
    source .env
    
    # 检查ECR仓库是否存在
    if aws ecr describe-repositories --repository-names mountpoint-s3-app --region $AWS_REGION &> /dev/null; then
        echo "✅ ECR仓库存在"
        
        # 检查镜像是否存在
        if aws ecr describe-images --repository-name mountpoint-s3-app --region $AWS_REGION --image-ids imageTag=latest &> /dev/null; then
            echo "✅ Docker镜像已推送"
        else
            echo "❌ Docker镜像未推送"
            return 1
        fi
    else
        echo "❌ ECR仓库不存在"
        return 1
    fi
}

# 检查Terraform配置
check_terraform_config() {
    echo "5. 检查Terraform配置..."
    
    cd terraform
    
    # 检查terraform.tfvars格式
    if terraform fmt -check=true terraform.tfvars &> /dev/null; then
        echo "✅ terraform.tfvars格式正确"
    else
        echo "⚠️  terraform.tfvars格式需要调整"
        terraform fmt terraform.tfvars
    fi
    
    # 初始化（如果需要）
    if [ ! -d ".terraform" ]; then
        echo "初始化Terraform..."
        if terraform init; then
            echo "✅ Terraform初始化成功"
        else
            echo "❌ Terraform初始化失败"
            cd ..
            return 1
        fi
    fi
    
    # 验证配置
    if terraform validate; then
        echo "✅ Terraform配置有效"
    else
        echo "❌ Terraform配置无效"
        cd ..
        return 1
    fi
    
    cd ..
}

# 检查网络连接
check_network_connectivity() {
    echo "6. 检查网络连接..."
    
    local endpoints=(
        "s3.amazonaws.com"
        "ecr.amazonaws.com"
        "ecs.amazonaws.com"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if curl -s --connect-timeout 5 "https://$endpoint" > /dev/null; then
            echo "✅ $endpoint 连接正常"
        else
            echo "❌ $endpoint 连接失败"
            return 1
        fi
    done
}

# 显示部署摘要
show_deployment_summary() {
    echo ""
    echo "=== 部署摘要 ==="
    
    source .env
    
    echo "项目名称: ecs-s3-test"
    echo "AWS区域: $AWS_REGION"
    echo "VPC ID: $VPC_ID"
    echo "ECR仓库: $APP_ECR_REPOSITORY_URL"
    
    # 计算子网数量
    subnet_count=$(echo $SUBNET_IDS | grep -o 'subnet-[^"]*' | wc -l)
    echo "子网数量: $subnet_count"
    
    echo ""
    echo "准备部署的资源:"
    echo "- ECS集群和服务"
    echo "- Application Load Balancer"
    echo "- S3存储桶"
    echo "- IAM角色和策略"
    echo "- CloudWatch日志组"
}

# 主函数
main() {
    echo "开始部署前检查..."
    
    local checks=(
        "check_required_files"
        "check_environment_variables"
        "check_aws_credentials"
        "check_docker_images"
        "check_terraform_config"
        "check_network_connectivity"
    )
    
    for check in "${checks[@]}"; do
        if ! $check; then
            echo ""
            echo "❌ 检查失败: $check"
            echo "请修复上述问题后重新运行"
            exit 1
        fi
        echo ""
    done
    
    show_deployment_summary
    
    echo ""
    echo "🎉 所有检查通过！"
    echo ""
    echo "现在可以安全地运行部署:"
    echo "  ./scripts/deploy.sh"
}

main "$@"
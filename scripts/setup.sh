#!/bin/bash

set -e

echo "=== ECS S3挂载测试项目设置脚本 ==="

# 检查必要的工具
check_dependencies() {
    echo "检查依赖工具..."
    
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI未安装，请先安装AWS CLI"
        exit 1
    fi
    
    if ! command -v terraform &> /dev/null; then
        echo "❌ Terraform未安装，请先安装Terraform"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker未安装，请先安装Docker"
        exit 1
    fi
    
    echo "✅ 依赖工具检查完成"
}

# 检查AWS凭证
check_aws_credentials() {
    echo "检查AWS凭证..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS凭证未配置或无效"
        echo "请运行: aws configure"
        exit 1
    fi
    
    echo "✅ AWS凭证验证成功"
}

# 创建ECR仓库
create_ecr_repository() {
    echo "创建ECR仓库..."
    
    AWS_REGION=${AWS_REGION:-us-west-2}
    
    # 创建应用仓库
    APP_REPO_NAME="mountpoint-s3-app"
    if aws ecr describe-repositories --repository-names $APP_REPO_NAME --region $AWS_REGION &> /dev/null; then
        echo "✅ 应用ECR仓库已存在: $APP_REPO_NAME"
    else
        aws ecr create-repository --repository-name $APP_REPO_NAME --region $AWS_REGION
        echo "✅ 应用ECR仓库创建成功: $APP_REPO_NAME"
    fi
    APP_ECR_URI=$(aws ecr describe-repositories --repository-names $APP_REPO_NAME --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
    
    echo "应用仓库URI: $APP_ECR_URI"
    
    # 保存到环境文件
    echo "APP_ECR_REPOSITORY_URL=$APP_ECR_URI" > .env
    echo "AWS_REGION=$AWS_REGION" >> .env
}

# 构建并推送Docker镜像
build_and_push_images() {
    echo "构建并推送Docker镜像..."
    
    source .env
    
    # 登录ECR
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $APP_ECR_REPOSITORY_URL
    
    # 构建Mountpoint-S3应用镜像
    echo "构建Mountpoint-S3应用镜像..."
    if docker build -t mountpoint-s3-app ./apps/app/; then
        echo "✅ 应用镜像构建成功"
    else
        echo "⚠️  主Dockerfile构建失败，尝试备用版本..."
        docker build -f ./apps/app/Dockerfile.backup -t mountpoint-s3-app ./apps/app/
    fi
    docker tag mountpoint-s3-app:latest $APP_ECR_REPOSITORY_URL:latest
    docker push $APP_ECR_REPOSITORY_URL:latest
    
    echo "✅ 所有Docker镜像构建并推送成功"
}

# 获取默认VPC信息
get_vpc_info() {
    echo "获取VPC信息..."
    
    AWS_REGION=${AWS_REGION:-us-west-2}
    
    # 获取默认VPC
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --region $AWS_REGION --query 'Vpcs[0].VpcId' --output text)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        echo "❌ 未找到默认VPC，请手动指定VPC_ID"
        exit 1
    fi
    
    # 获取公共子网
    SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" --region $AWS_REGION --query 'Subnets[].SubnetId' --output text)
    
    if [ -z "$SUBNET_IDS" ]; then
        echo "❌ 未找到公共子网"
        exit 1
    fi
    
    # 转换为Terraform数组格式（带引号）
    SUBNET_ARRAY="[\"$(echo $SUBNET_IDS | sed 's/ /","/g')\"]"
    
    echo "VPC_ID=$VPC_ID" >> .env
    echo "SUBNET_IDS=$SUBNET_ARRAY" >> .env
    
    echo "✅ VPC信息获取成功"
    echo "  VPC ID: $VPC_ID"
    echo "  子网IDs: $SUBNET_ARRAY"
}

# 创建terraform.tfvars文件
create_terraform_vars() {
    echo "创建Terraform变量文件..."
    
    source .env
    
    # 手动构建正确格式的terraform.tfvars
    cat > terraform/terraform.tfvars << EOF
project_name = "ecs-s3-test"
aws_region = "$AWS_REGION"
vpc_id = "$VPC_ID"
subnet_ids = $SUBNET_IDS
app_ecr_repository_url = "$APP_ECR_REPOSITORY_URL"
EOF
    
    # 验证生成的文件格式
    echo "验证生成的terraform.tfvars格式..."
    if grep -q 'subnet_ids = \["subnet-.*"\]' terraform/terraform.tfvars; then
        echo "✅ subnet_ids格式正确"
    else
        echo "❌ subnet_ids格式错误，手动修复..."
        
        # 重新读取子网ID并格式化
        SUBNET_LIST=$(echo "$SUBNET_IDS" | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g')
        FORMATTED_SUBNETS="["
        first=true
        for subnet in $(echo $SUBNET_LIST | tr ',' ' '); do
            if [ "$first" = true ]; then
                FORMATTED_SUBNETS="$FORMATTED_SUBNETS\"$subnet\""
                first=false
            else
                FORMATTED_SUBNETS="$FORMATTED_SUBNETS,\"$subnet\""
            fi
        done
        FORMATTED_SUBNETS="$FORMATTED_SUBNETS]"
        
        # 重新生成文件
        cat > terraform/terraform.tfvars << EOF
project_name = "ecs-s3-test"
aws_region = "$AWS_REGION"
vpc_id = "$VPC_ID"
subnet_ids = $FORMATTED_SUBNETS
app_ecr_repository_url = "$APP_ECR_REPOSITORY_URL"
EOF
    fi
    
    echo "✅ Terraform变量文件创建成功"
    echo "生成的terraform.tfvars内容:"
    cat terraform/terraform.tfvars
}

# 上传测试数据到S3
upload_test_data() {
    echo "准备测试数据..."
    
    # 创建临时测试文件
    mkdir -p temp_test_data
    echo "这是一个测试文件" > temp_test_data/sample.txt
    echo "Hello World" > temp_test_data/hello.txt
    
    # 创建一个较大的测试文件
    dd if=/dev/zero of=temp_test_data/large_file.bin bs=1024 count=1024 2>/dev/null
    
    echo "✅ 测试数据准备完成"
}

# 主函数
main() {
    echo "开始设置ECS S3挂载测试项目..."
    
    check_dependencies
    check_aws_credentials
    create_ecr_repository
    build_and_push_images
    get_vpc_info
    create_terraform_vars
    upload_test_data
    
    echo ""
    echo "🎉 项目设置完成！"
    echo ""
    echo "下一步操作："
    echo "1. 运行 './scripts/deploy.sh' 部署基础设施"
    echo "2. 运行 './scripts/test.sh' 执行测试"
    echo ""
    echo "配置文件已保存到 .env 和 terraform/terraform.tfvars"
}

main "$@"
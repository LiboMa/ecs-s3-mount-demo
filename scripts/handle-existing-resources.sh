#!/bin/bash

set -e

echo "=== 处理已存在的AWS资源 ==="
echo ""
echo "选择处理方式:"
echo "1. 导入现有资源到Terraform状态 (推荐)"
echo "2. 删除现有资源并重新创建"
echo "3. 跳过已存在的资源"
echo ""

read -p "请选择 (1-3): " choice

case $choice in
    1)
        echo "选择: 导入现有资源"
        ./scripts/import-existing-resources.sh
        ;;
    2)
        echo "选择: 删除现有资源"
        echo "⚠️  警告: 这将删除现有的AWS资源!"
        read -p "确认删除? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            ./scripts/cleanup.sh
            echo "现在可以重新运行部署脚本"
        else
            echo "取消删除操作"
            exit 1
        fi
        ;;
    3)
        echo "选择: 跳过已存在的资源"
        echo "将使用 terraform apply -target 来部署新资源..."
        
        cd terraform
        
        # 只部署新的资源
        echo "部署新的EC2相关资源..."
        terraform apply -target=aws_ecs_capacity_provider.ec2 \
                       -target=aws_autoscaling_group.ecs_ec2 \
                       -target=aws_launch_template.ecs_ec2 \
                       -target=aws_iam_role.ecs_ec2_role \
                       -target=aws_iam_instance_profile.ecs_ec2 \
                       -target=aws_security_group.ecs_ec2 \
                       -auto-approve
        
        cd ..
        echo "✅ 新资源部署完成"
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo ""
echo "🎉 资源处理完成!"
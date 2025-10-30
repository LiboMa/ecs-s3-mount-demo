#!/bin/bash

set -e

echo "=== Terraform配置验证脚本 ==="

cd terraform

echo "1. 检查Terraform配置语法..."
if terraform fmt -check=true -diff=true; then
    echo "✅ Terraform格式正确"
else
    echo "❌ Terraform格式需要修复"
    echo "运行 'terraform fmt' 来修复格式"
fi

echo ""
echo "2. 初始化Terraform（如果需要）..."
if [ ! -d ".terraform" ]; then
    echo "初始化Terraform..."
    terraform init
else
    echo "✅ Terraform已初始化"
fi

echo ""
echo "3. 验证Terraform配置..."
if terraform validate; then
    echo "✅ Terraform配置验证通过"
else
    echo "❌ Terraform配置验证失败"
    exit 1
fi

echo ""
echo "4. 检查terraform.tfvars文件..."
if [ -f "terraform.tfvars" ]; then
    echo "✅ terraform.tfvars文件存在"
    echo "内容预览:"
    cat terraform.tfvars
else
    echo "❌ terraform.tfvars文件不存在"
    echo "请运行 ./scripts/regenerate-tfvars.sh 生成配置文件"
    exit 1
fi

echo ""
echo "5. 生成执行计划（dry-run）..."
if terraform plan -out=tfplan; then
    echo "✅ Terraform计划生成成功"
    echo ""
    echo "如果要应用更改，请运行:"
    echo "  cd terraform && terraform apply tfplan"
else
    echo "❌ Terraform计划生成失败"
    exit 1
fi

cd ..
echo ""
echo "🎉 Terraform配置验证完成！"
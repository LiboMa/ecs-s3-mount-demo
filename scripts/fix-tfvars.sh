#!/bin/bash

set -e

echo "=== 修复terraform.tfvars格式脚本 ==="

# 检查文件是否存在
if [ ! -f terraform/terraform.tfvars ]; then
    echo "❌ terraform.tfvars文件不存在"
    exit 1
fi

echo "当前terraform.tfvars内容:"
cat terraform/terraform.tfvars
echo ""

# 修复subnet_ids格式
fix_subnet_ids() {
    echo "修复subnet_ids格式..."
    
    # 提取当前的subnet_ids行
    current_line=$(grep "subnet_ids = " terraform/terraform.tfvars)
    echo "当前格式: $current_line"
    
    # 提取子网ID列表
    subnet_list=$(echo "$current_line" | sed 's/subnet_ids = \[//g' | sed 's/\]//g' | sed 's/,/ /g')
    
    # 重新格式化为正确的Terraform格式
    formatted_subnets="["
    first=true
    
    for subnet in $subnet_list; do
        # 移除可能存在的引号
        clean_subnet=$(echo $subnet | sed 's/"//g')
        
        if [ "$first" = true ]; then
            formatted_subnets="$formatted_subnets\"$clean_subnet\""
            first=false
        else
            formatted_subnets="$formatted_subnets,\"$clean_subnet\""
        fi
    done
    
    formatted_subnets="$formatted_subnets]"
    
    echo "修复后格式: subnet_ids = $formatted_subnets"
    
    # 替换文件中的行
    sed -i.bak "s|subnet_ids = .*|subnet_ids = $formatted_subnets|" terraform/terraform.tfvars
    
    echo "✅ subnet_ids格式已修复"
}

# 验证修复结果
verify_fix() {
    echo "验证修复结果..."
    
    echo "修复后的terraform.tfvars内容:"
    cat terraform/terraform.tfvars
    echo ""
    
    # 检查格式是否正确
    if grep -q 'subnet_ids = \["subnet-.*"\]' terraform/terraform.tfvars; then
        echo "✅ subnet_ids格式正确"
        return 0
    else
        echo "❌ subnet_ids格式仍然错误"
        return 1
    fi
}

# 测试Terraform验证
test_terraform_validation() {
    echo "测试Terraform验证..."
    
    cd terraform
    
    # 初始化（如果需要）
    if [ ! -d ".terraform" ]; then
        echo "初始化Terraform..."
        terraform init
    fi
    
    # 验证配置
    if terraform validate; then
        echo "✅ Terraform配置验证通过"
        cd ..
        return 0
    else
        echo "❌ Terraform配置验证失败"
        cd ..
        return 1
    fi
}

# 主函数
main() {
    echo "开始修复terraform.tfvars格式问题..."
    
    fix_subnet_ids
    
    if verify_fix; then
        echo "格式修复成功，测试Terraform验证..."
        
        if test_terraform_validation; then
            echo ""
            echo "🎉 terraform.tfvars修复完成！"
            echo ""
            echo "现在可以运行:"
            echo "  ./scripts/deploy.sh"
        else
            echo "❌ 仍有配置问题，请检查Terraform文件"
            exit 1
        fi
    else
        echo "❌ 格式修复失败"
        exit 1
    fi
}

main "$@"
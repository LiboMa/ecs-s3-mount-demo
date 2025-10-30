#!/bin/bash

set -e

echo "=== Terraform初始化脚本 ==="

# 检查terraform.tfvars文件
check_prerequisites() {
    echo "1. 检查前置条件..."
    
    if [ ! -f terraform/terraform.tfvars ]; then
        echo "❌ terraform.tfvars文件不存在"
        echo "请先运行 ./scripts/setup.sh"
        exit 1
    fi
    
    if [ ! -f .env ]; then
        echo "❌ .env文件不存在"
        echo "请先运行 ./scripts/setup.sh"
        exit 1
    fi
    
    echo "✅ 前置条件检查通过"
}

# 初始化Terraform
init_terraform() {
    echo "2. 初始化Terraform..."
    
    cd terraform
    
    # 清理旧的状态（如果需要）
    if [ "$1" = "--clean" ]; then
        echo "清理旧的Terraform状态..."
        rm -rf .terraform/
        rm -f .terraform.lock.hcl
    fi
    
    # 初始化
    if terraform init; then
        echo "✅ Terraform初始化成功"
    else
        echo "❌ Terraform初始化失败"
        cd ..
        exit 1
    fi
    
    cd ..
}

# 验证配置
validate_config() {
    echo "3. 验证Terraform配置..."
    
    cd terraform
    
    # 格式化检查
    if terraform fmt -check=true; then
        echo "✅ Terraform格式正确"
    else
        echo "⚠️  自动格式化Terraform文件..."
        terraform fmt
    fi
    
    # 配置验证
    if terraform validate; then
        echo "✅ Terraform配置验证通过"
    else
        echo "❌ Terraform配置验证失败"
        cd ..
        exit 1
    fi
    
    cd ..
}

# 显示计划预览
show_plan() {
    echo "4. 生成部署计划..."
    
    cd terraform
    
    if terraform plan -out=tfplan; then
        echo "✅ 部署计划生成成功"
        echo ""
        echo "计划文件已保存为: terraform/tfplan"
        echo "可以使用以下命令应用:"
        echo "  cd terraform && terraform apply tfplan"
    else
        echo "❌ 部署计划生成失败"
        cd ..
        exit 1
    fi
    
    cd ..
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --clean    清理旧的Terraform状态后重新初始化"
    echo "  --plan     生成部署计划"
    echo "  --help     显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                # 标准初始化和验证"
    echo "  $0 --clean        # 清理后重新初始化"
    echo "  $0 --plan         # 初始化并生成计划"
}

# 主函数
main() {
    local clean_mode=false
    local plan_mode=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                clean_mode=true
                shift
                ;;
            --plan)
                plan_mode=true
                shift
                ;;
            --help)
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
    
    echo "开始Terraform初始化流程..."
    
    check_prerequisites
    
    if [ "$clean_mode" = true ]; then
        init_terraform --clean
    else
        init_terraform
    fi
    
    validate_config
    
    if [ "$plan_mode" = true ]; then
        show_plan
    fi
    
    echo ""
    echo "🎉 Terraform初始化完成！"
    echo ""
    echo "下一步操作:"
    echo "  ./scripts/deploy.sh    # 部署基础设施"
    echo "  或者"
    echo "  cd terraform && terraform apply"
}

main "$@"
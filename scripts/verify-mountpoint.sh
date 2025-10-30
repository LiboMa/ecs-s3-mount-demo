#!/bin/bash

set -e

echo "=== Mountpoint-S3安装验证脚本 ==="

# 检查mount-s3命令是否可用
check_mountpoint_command() {
    echo "1. 检查mount-s3命令..."
    
    if command -v mount-s3 &> /dev/null; then
        echo "✅ mount-s3命令可用"
        mount-s3 --version
    else
        echo "❌ mount-s3命令不可用"
        return 1
    fi
}

# 检查RPM包信息
check_rpm_package() {
    echo "2. 检查RPM包信息..."
    
    if rpm -qa | grep -q mount-s3; then
        echo "✅ Mountpoint-S3 RPM包已安装"
        rpm -qi mount-s3 2>/dev/null || echo "⚠️  无法获取RPM包详细信息"
    else
        echo "❌ Mountpoint-S3 RPM包未安装"
        return 1
    fi
}

# 检查依赖
check_dependencies() {
    echo "3. 检查系统依赖..."
    
    # 检查FUSE
    if [ -c /dev/fuse ]; then
        echo "✅ FUSE设备可用"
    else
        echo "⚠️  FUSE设备不可用"
    fi
    
    # 检查curl
    if command -v curl &> /dev/null; then
        echo "✅ curl可用"
    else
        echo "❌ curl不可用"
    fi
}

# 测试基本功能（如果有AWS凭证）
test_basic_functionality() {
    echo "4. 测试基本功能..."
    
    # 检查帮助信息
    if mount-s3 --help &> /dev/null; then
        echo "✅ 帮助信息正常"
    else
        echo "⚠️  帮助信息异常"
    fi
    
    # 如果有AWS凭证，可以尝试列出存储桶
    if aws sts get-caller-identity &> /dev/null 2>&1; then
        echo "✅ AWS凭证可用，可以进行实际挂载测试"
    else
        echo "⚠️  AWS凭证不可用，跳过实际挂载测试"
    fi
}

# 显示安装信息
show_installation_info() {
    echo ""
    echo "=== 安装信息 ==="
    echo "Mountpoint-S3版本: $(mount-s3 --version 2>/dev/null || echo '未知')"
    echo "安装路径: $(which mount-s3 2>/dev/null || echo '未找到')"
    echo "RPM包信息:"
    rpm -qi mount-s3 2>/dev/null | grep -E "(Name|Version|Release|Install Date)" || echo "无RPM信息"
}

# 主函数
main() {
    echo "开始验证Mountpoint-S3安装..."
    
    check_mountpoint_command
    check_rpm_package
    check_dependencies
    test_basic_functionality
    show_installation_info
    
    echo ""
    echo "🎉 Mountpoint-S3安装验证完成！"
}

main "$@"
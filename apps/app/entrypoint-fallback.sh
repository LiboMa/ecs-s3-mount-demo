#!/bin/bash

set -e

echo "=== Mountpoint-S3 Flask API应用启动 (带回退机制) ==="

# 检查环境变量
if [ -z "$S3_BUCKET_NAME" ]; then
    echo "错误: 未设置S3_BUCKET_NAME环境变量"
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo "错误: 未设置AWS_REGION环境变量"
    exit 1
fi

# 简化的FUSE检查（可选）
check_fuse_support() {
    echo "检查FUSE支持..."
    
    # 简单检查/dev/fuse设备
    if [ -c /dev/fuse ]; then
        echo "✅ FUSE设备可用"
        return 0
    else
        echo "❌ FUSE设备不可用"
        return 1
    fi
}

# 尝试Mountpoint-S3挂载
try_mountpoint_mount() {
    echo "尝试使用Mountpoint-S3挂载..."
    
    # Mountpoint-S3挂载选项
    MOUNT_OPTIONS="--cache /tmp/mountpoint-cache --part-size 16MB"
    
    # 如果设置为只读模式
    if [ "$READ_ONLY" = "true" ]; then
        echo "使用只读模式挂载"
    else
        MOUNT_OPTIONS="$MOUNT_OPTIONS --allow-delete --allow-overwrite"
    fi
    
    # 创建缓存目录
    mkdir -p /tmp/mountpoint-cache
    
    # 执行挂载
    if mount-s3 $MOUNT_OPTIONS $S3_BUCKET_NAME /mnt/s3-mp 2>/dev/null; then
        echo "✅ Mountpoint-S3挂载成功"
        return 0
    else
        echo "❌ Mountpoint-S3挂载失败"
        return 1
    fi
}

# 回退到S3 API模式
setup_s3_api_mode() {
    echo "⚠️  回退到S3 API直接访问模式"
    
    # 创建虚拟挂载点标记
    mkdir -p /mnt/s3-mp
    echo "# S3 API模式 - 此目录不是真实挂载点" > /mnt/s3-mp/.s3-api-mode
    
    # 设置环境变量标识
    export S3_MOUNT_PATH="/mnt/s3-mp"
    export MOUNT_TYPE="s3-api-fallback"
    export USE_S3_API="true"
    
    echo "✅ S3 API模式设置完成"
    return 0
}

# 主挂载逻辑
main_mount() {
    # 检查FUSE支持
    if check_fuse_support; then
        # 尝试Mountpoint-S3挂载
        if try_mountpoint_mount; then
            # 验证挂载
            if mountpoint -q /mnt/s3-mp; then
                echo "✅ Mountpoint-S3挂载验证成功"
                echo "挂载信息:"
                df -h /mnt/s3-mp
                echo "文件列表预览:"
                ls -la /mnt/s3-mp | head -10
                
                # 设置环境变量
                export S3_MOUNT_PATH="/mnt/s3-mp"
                export MOUNT_TYPE="mountpoint-s3"
                return 0
            fi
        fi
    fi
    
    # 如果挂载失败，回退到S3 API模式
    echo "Mountpoint-S3挂载不可用，使用S3 API模式"
    setup_s3_api_mode
    return 0
}

# 执行挂载
main_mount

# 启动Flask应用
echo "启动Flask API应用..."
echo "挂载类型: ${MOUNT_TYPE}"
echo "挂载路径: ${S3_MOUNT_PATH}"

cd /app
exec gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 60 --access-logfile - --error-logfile - app:app
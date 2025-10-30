#!/bin/bash

set -e

echo "=== Mountpoint-S3 Flask API应用启动 ==="

# 检查环境变量
if [ -z "$S3_BUCKET_NAME" ]; then
    echo "错误: 未设置S3_BUCKET_NAME环境变量"
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo "错误: 未设置AWS_REGION环境变量"
    exit 1
fi

# 使用Mountpoint-S3挂载S3存储桶
echo "正在使用Mountpoint-S3挂载S3存储桶: $S3_BUCKET_NAME"

# Mountpoint-S3挂载选项 (读写模式)
# MOUNT_OPTIONS="--cache /tmp/mountpoint-cache --allow-delete --allow-overwrite"

echo "使用读写模式挂载"

# 创建缓存目录
mkdir -p /tmp/mountpoint-cache

# 执行挂载
# echo "执行挂载命令: mount-s3 $MOUNT_OPTIONS $S3_BUCKET_NAME /mnt/s3data"
# mount-s3 $MOUNT_OPTIONS $S3_BUCKET_NAME /mnt/s3data
mount-s3 $S3_BUCKET_NAME /mnt/s3data --region $AWS_REGION

# 验证挂载
if [ -e /mnt/s3data ]; then
    echo "✅ Mountpoint-S3挂载成功"
    echo "挂载信息:"
    df -h /mnt/s3data
    echo "文件列表预览:"
    ls -la /mnt/s3data | head -10
else
    echo "❌ Mountpoint-S3挂载失败"
    exit 1
fi

# 设置环境变量
export S3_MOUNT_PATH="/mnt/s3data"
export MOUNT_TYPE="mountpoint-s3"

# 启动Flask应用
echo "启动Mountpoint-S3 Flask API应用..."
cd /app
exec gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 60 --access-logfile - --error-logfile - app:app
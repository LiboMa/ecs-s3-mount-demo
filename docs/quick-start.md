# 快速开始指南

## 项目简介
使用AWS Mountpoint-S3在ECS容器中实现高性能S3文件系统挂载，提供Flask API访问。

## 核心特性
- 🚀 **高性能**: Mountpoint-S3官方优化
- 🐳 **容器化**: ECS EC2部署
- 🔗 **API访问**: RESTful接口
- ⚡ **简单部署**: 一键式脚本
- 📦 **RPM安装**: 使用官方RPM包，更稳定可靠

## 快速部署

### 1. 环境准备
```bash
# 确保已安装并配置
- AWS CLI
- Docker
- Terraform
```

### 2. 一键部署
```bash
# 克隆项目
git clone <repository>
cd ECS_MountingS3

# 设置环境
./scripts/setup.sh

# 部署基础设施
./scripts/deploy.sh

# 测试应用
./scripts/test-app.sh

# 测试读写功能
./scripts/test-readwrite.sh
```

### 3. 访问应用
部署完成后，获取应用URL：
```bash
# 从Terraform输出获取
cd terraform
terraform output app_url
```

## API使用示例

### 健康检查
```bash
curl http://<app-url>/health
```

### 列出文件
```bash
curl http://<app-url>/api/files
```

### 获取文件信息
```bash
curl http://<app-url>/api/files/sample.txt
```

### 下载文件
```bash
curl "http://<app-url>/api/files/sample.txt/content?download=true" -O
```

### 写入文件
```bash
curl -X PUT http://<app-url>/api/files/new_file.txt/content \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello World!"}'
```

### 上传文件
```bash
curl -X POST http://<app-url>/api/files/upload.jpg/content \
  -F "file=@local_image.jpg"
```

### 创建目录
```bash
curl -X POST http://<app-url>/api/files \
  -H "Content-Type: application/json" \
  -d '{"action": "create_directory", "name": "new_folder"}'
```

### 删除文件
```bash
curl -X DELETE http://<app-url>/api/files/unwanted_file.txt
```

## 架构说明

```
Internet → ALB → ECS EC2 → Mountpoint-S3 → S3 Bucket
                    ↓
                Flask API
```

- **ALB**: 应用负载均衡器
- **ECS EC2**: 容器运行环境（支持FUSE）
- **Mountpoint-S3**: 高性能S3挂载
- **Flask API**: RESTful接口服务

## 清理资源
```bash
./scripts/cleanup.sh
```

## 故障排查

### 常见问题
1. **挂载失败**: 检查IAM权限和S3存储桶访问
2. **健康检查失败**: 等待应用完全启动（约2-3分钟）
3. **网络问题**: 确认安全组和VPC配置

### 查看日志
```bash
# ECS任务日志
aws logs tail /ecs/ecs-s3-test --follow

# 或通过AWS控制台查看ECS服务日志
```

## 配置选项

### 环境变量
- `S3_BUCKET_NAME`: S3存储桶名称
- `AWS_REGION`: AWS区域
- `READ_ONLY`: 只读模式（可选）
- `MAX_FILES`: 最大文件列表数量

### 挂载选项
- `--cache`: 本地缓存目录
- `--part-size`: 分块大小
- `--allow-delete`: 允许删除操作
- `--allow-overwrite`: 允许覆盖操作

## 性能优化

### 缓存配置
```bash
# 增加缓存大小
--cache /tmp/cache --max-cache-size 10GB
```

### 并发配置
```bash
# 调整Gunicorn workers
gunicorn --workers 4 --timeout 120
```

### 网络优化
```bash
# 使用VPC端点减少延迟
# 选择就近的AWS区域
```
# 故障排查指南

## Docker构建问题

### 问题1: Flask版本不存在
```
ERROR: No matching distribution found for Flask==2.3.3
```

**解决方案:**
1. 使用版本范围而不是固定版本
2. 升级pip到最新版本
3. 使用备用Dockerfile

**修复步骤:**
```bash
# 测试Docker构建
./scripts/test-docker-build.sh

# 如果失败，手动测试
docker build -t test-build ./apps/s3fs-api/

# 使用备用Dockerfile
docker build -f ./apps/s3fs-api/Dockerfile.backup -t test-build ./apps/s3fs-api/
```

### 问题2: useradd命令不存在
```
/bin/sh: useradd: command not found
```

**解决方案:**
在我们的场景中，不需要创建非root用户：
- S3挂载需要特殊权限
- 容器环境相对安全
- 简化部署和调试

**修复:** 移除非root用户创建，直接以root运行

### 问题3: Python包安装失败
**可能原因:**
- 网络连接问题
- pip版本过旧
- 依赖冲突

**解决方案:**
```bash
# 在Dockerfile中添加
RUN pip3 install --upgrade pip setuptools wheel

# 或使用简化版requirements
Flask
Flask-CORS
gunicorn
```

### 问题3: FUSE不支持错误
```
fuse: device not found, try 'modprobe fuse' first
Error: Failed to create FUSE session
```

**原因分析:**
- ECS Fargate不支持FUSE文件系统
- 容器缺少SYS_ADMIN权限
- FUSE内核模块未加载

**解决方案:**

1. **确保使用ECS EC2启动类型**
```bash
# 项目已配置为使用EC2
requires_compatibilities = ["EC2"]
```

2. **确认SYS_ADMIN权限**
```json
"linuxParameters": {
  "capabilities": {
    "add": ["SYS_ADMIN"]
  }
}
```

3. **检查挂载命令**
```bash
# 在容器中手动测试
mount-s3 --version
mount-s3 bucket-name /mnt/test
```

### 问题4: Mountpoint-S3安装失败
```
curl: (7) Failed to connect to s3.amazonaws.com
```

**解决方案:**
```bash
# 检查网络连接
curl -I https://s3.amazonaws.com

# 手动下载和安装
curl -O https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
yum install -y ./mount-s3.rpm

# 验证安装
mount-s3 --version
```

**RPM安装优势:**
- 更好的依赖管理
- 系统集成更完整
- 卸载更干净

## AWS部署问题

### 问题1: Terraform Provider未初始化
```
Error: Missing required provider
This configuration requires provider registry.terraform.io/hashicorp/aws
```

**原因**: Terraform需要先初始化才能验证配置

**解决方案:**
```bash
# 正确的执行顺序
cd terraform
terraform init      # 先初始化
terraform validate  # 再验证
terraform plan      # 最后规划

# 或使用检查脚本
./scripts/pre-deploy-check.sh
```

### 问题2: ECR推送失败
```
denied: User is not authorized to perform: ecr:BatchCheckLayerAvailability
```

**解决方案:**
```bash
# 检查AWS凭证
aws sts get-caller-identity

# 重新登录ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <ecr-uri>

# 检查IAM权限
aws iam list-attached-user-policies --user-name <username>
```

### 问题2: ECS任务启动失败
**常见原因:**
- 镜像不存在
- IAM权限不足
- 网络配置错误
- 资源不足

**排查步骤:**
```bash
# 检查任务状态
aws ecs describe-tasks --cluster <cluster> --tasks <task-arn>

# 查看任务日志
aws logs get-log-events --log-group-name /ecs/ecs-s3-test --log-stream-name <stream>

# 检查服务事件
aws ecs describe-services --cluster <cluster> --services <service>
```

### 问题3: S3挂载失败
```
s3fs: MOUNTPOINT directory /mnt/s3-s3fs is not empty.
```

**解决方案:**
```bash
# 在entrypoint.sh中添加清理
rm -rf /mnt/s3-s3fs/*
mkdir -p /mnt/s3-s3fs

# 检查IAM权限
aws s3 ls s3://bucket-name

# 验证区域设置
aws s3api get-bucket-location --bucket bucket-name
```

## 网络连接问题

### 问题1: 健康检查失败
```
Health check failed
```

**排查步骤:**
```bash
# 检查应用是否启动
curl -f http://localhost:5000/health

# 检查端口监听
netstat -tlnp | grep 5000

# 检查安全组规则
aws ec2 describe-security-groups --group-ids <sg-id>
```

### 问题2: ALB无法访问
**可能原因:**
- 目标组健康检查失败
- 安全组配置错误
- 子网配置问题

**解决方案:**
```bash
# 检查目标组健康状态
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# 检查ALB状态
aws elbv2 describe-load-balancers --load-balancer-arns <alb-arn>

# 测试直接连接
curl -v http://<alb-dns>/health
```

## 性能问题

### 问题1: API响应慢
**可能原因:**
- S3挂载性能问题
- 缓存配置不当
- 网络延迟

**优化方案:**
```bash
# S3FS-FUSE优化
s3fs bucket /mnt/s3 -o use_cache=/tmp/cache -o parallel_count=10

# Mountpoint-S3优化
mount-s3 --cache /tmp/cache --part-size 16MB bucket /mnt/s3

# 监控性能
iostat -x 1
top -p $(pgrep gunicorn)
```

### 问题2: 内存使用过高
**解决方案:**
```bash
# 调整Gunicorn配置
gunicorn --workers 1 --max-requests 1000 --timeout 30

# 限制缓存大小
s3fs bucket /mnt/s3 -o use_cache=/tmp/cache -o cache_size_mb=100

# 监控内存使用
free -h
ps aux --sort=-%mem | head
```

## 调试技巧

### 1. 启用详细日志
```bash
# 在entrypoint.sh中添加
export FLASK_DEBUG=true
export S3FS_DEBUG=1

# 或在Dockerfile中
ENV FLASK_DEBUG=true
```

### 2. 交互式调试
```bash
# 运行交互式容器
docker run -it --rm s3fs-api /bin/bash

# 手动测试挂载
s3fs bucket-name /mnt/s3 -o iam_role=auto -f -d

# 测试Flask应用
python3 app.py
```

### 3. 本地测试
```bash
# 使用LocalStack模拟S3
docker run -d -p 4566:4566 localstack/localstack

# 配置本地端点
export AWS_ENDPOINT_URL=http://localhost:4566
aws s3 mb s3://test-bucket --endpoint-url http://localhost:4566
```

## 常用命令

### Docker相关
```bash
# 查看容器日志
docker logs <container-id>

# 进入运行中的容器
docker exec -it <container-id> /bin/bash

# 清理Docker资源
docker system prune -a
```

### AWS相关
```bash
# 查看ECS任务日志
aws logs tail /ecs/ecs-s3-test --follow

# 重启ECS服务
aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment

# 查看CloudFormation事件
aws cloudformation describe-stack-events --stack-name <stack>
```

### 网络诊断
```bash
# 测试DNS解析
nslookup s3.amazonaws.com

# 测试网络连接
telnet s3.amazonaws.com 443

# 查看路由
traceroute s3.amazonaws.com
```

## 预防措施

### 1. 版本锁定
```bash
# 在requirements.txt中使用版本范围
Flask>=2.0.0,<3.0.0

# 定期更新依赖
pip list --outdated
```

### 2. 健康检查
```bash
# 在Dockerfile中添加
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1
```

### 3. 资源监控
```bash
# 设置CloudWatch告警
aws cloudwatch put-metric-alarm \
  --alarm-name "ECS-CPU-High" \
  --alarm-description "ECS CPU utilization" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold
```

### 4. 备份策略
```bash
# 定期备份配置
aws ecs describe-task-definition --task-definition <family> > backup.json

# 版本控制
git tag -a v1.0 -m "Production release"
```
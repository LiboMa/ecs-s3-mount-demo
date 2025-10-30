# 项目结构说明

## 目录结构
```
ECS_MountingS3/
├── apps/                          # 应用程序
│   ├── s3fs-api/                 # S3FS-FUSE Flask API应用
│   │   ├── Dockerfile            # S3FS-FUSE容器镜像
│   │   ├── app.py               # Flask应用代码
│   │   ├── requirements.txt     # Python依赖
│   │   └── entrypoint.sh        # S3FS-FUSE启动脚本
│   └── mountpoint-api/          # Mountpoint-S3 Flask API应用
│       ├── Dockerfile           # Mountpoint-S3容器镜像
│       ├── app.py              # Flask应用代码
│       ├── requirements.txt    # Python依赖
│       └── entrypoint.sh       # Mountpoint-S3启动脚本
├── terraform/                   # 基础设施即代码
│   ├── main.tf                 # 主要资源定义
│   ├── ecs.tf                  # ECS相关资源
│   ├── variables.tf            # 变量定义
│   └── outputs.tf              # 输出定义
├── scripts/                     # 部署和测试脚本
│   ├── setup.sh               # 环境设置脚本
│   ├── deploy.sh              # 部署脚本
│   ├── test-s3fs-api.sh       # S3FS API测试
│   ├── test-mountpoint-api.sh  # Mountpoint API测试
│   ├── performance-comparison.sh # 性能对比
│   └── cleanup.sh             # 资源清理
├── tests/                      # 测试用例
│   ├── test_s3_operations.py   # S3操作测试
│   ├── test_performance.py     # 性能测试
│   └── test_mountpoint_performance.py # Mountpoint性能测试
├── docs/                       # 文档
│   ├── architecture.md         # 架构设计
│   ├── api-documentation.md    # API文档
│   ├── testing-guide.md        # 测试指南
│   ├── mount-solution-guide.md # 挂载方案指南
│   └── project-structure.md    # 项目结构说明
├── docker/                     # 传统测试容器
│   ├── Dockerfile             # S3测试容器
│   └── entrypoint.sh          # 测试容器启动脚本
└── README.md                   # 项目说明
```

## 应用架构

### S3FS-FUSE API应用
- **路径**: `apps/s3fs-api/`
- **挂载路径**: `/mnt/s3-s3fs`
- **特性**: 完整读写支持，POSIX兼容
- **适用场景**: 需要文件写入，传统应用兼容

### Mountpoint-S3 API应用
- **路径**: `apps/mountpoint-api/`
- **挂载路径**: `/mnt/s3-mp`
- **特性**: 极高性能，低资源消耗
- **适用场景**: 读取密集型，高性能需求

## 部署架构

```
┌─────────────────────────────────────────────────────────────┐
│                Application Load Balancer                    │
│                    (Port 80)                               │
├─────────────────────────┬───────────────────────────────────┤
│    Default Route        │     /mountpoint/* Route           │
│         ↓               │            ↓                      │
│  ┌─────────────────┐   │   ┌─────────────────┐            │
│  │ S3FS-FUSE API   │   │   │ Mountpoint-S3   │            │
│  │   ECS Service   │   │   │   ECS Service   │            │
│  │                 │   │   │                 │            │
│  │ Target Group    │   │   │ Target Group    │            │
│  │ Port 5000       │   │   │ Port 5000       │            │
│  └─────────────────┘   │   └─────────────────┘            │
└─────────────────────────┴───────────────────────────────────┘
```

## API访问路径

### S3FS-FUSE API
- **基础URL**: `http://<alb-dns>/`
- **健康检查**: `GET /health`
- **文件列表**: `GET /api/files`
- **文件信息**: `GET /api/files/{path}`

### Mountpoint-S3 API
- **基础URL**: `http://<alb-dns>/mountpoint/`
- **健康检查**: `GET /mountpoint/health`
- **文件列表**: `GET /mountpoint/api/files`
- **文件信息**: `GET /mountpoint/api/files/{path}`

## 环境变量配置

### 通用环境变量
```bash
S3_BUCKET_NAME=your-s3-bucket
AWS_REGION=us-west-2
PORT=5000
MAX_FILES=1000
```

### S3FS-FUSE特定
```bash
S3_MOUNT_PATH=/mnt/s3-s3fs
MOUNT_TYPE=s3fs-fuse
```

### Mountpoint-S3特定
```bash
S3_MOUNT_PATH=/mnt/s3data
MOUNT_TYPE=mountpoint-s3
READ_ONLY=false  # 可选，设置只读模式
```

### 安装方式
```dockerfile
# 使用官方RPM包安装
RUN curl -O https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
RUN yum install -y ./mount-s3.rpm
```

## 容器权限要求

### S3FS-FUSE容器
```json
{
  "linuxParameters": {
    "capabilities": {
      "add": ["SYS_ADMIN"]
    }
  }
}
```

### Mountpoint-S3容器
```json
{
  "linuxParameters": {
    "capabilities": {
      "add": ["SYS_ADMIN"]
    }
  }
}
```

## IAM权限要求

### ECS任务角色权限
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:HeadObject"
      ],
      "Resource": [
        "arn:aws:s3:::bucket-name",
        "arn:aws:s3:::bucket-name/*"
      ]
    }
  ]
}
```

## 网络配置

### 安全组规则
```
ALB安全组:
- 入站: TCP 80 from 0.0.0.0/0
- 出站: All traffic

ECS任务安全组:
- 入站: TCP 5000 from ALB安全组
- 出站: All traffic
```

### 子网要求
- 使用公共子网（需要访问S3和ECR）
- 每个可用区至少一个子网
- 启用自动分配公网IP

## 监控和日志

### CloudWatch日志组
- **日志组**: `/ecs/ecs-s3-test`
- **日志流前缀**:
  - S3FS API: `s3fs-api`
  - Mountpoint API: `mountpoint-api`
  - S3测试: `s3-test`

### 健康检查配置
```json
{
  "healthCheck": {
    "command": ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"],
    "interval": 30,
    "timeout": 5,
    "retries": 3,
    "startPeriod": 60
  }
}
```

## 性能调优

### S3FS-FUSE优化
```bash
# 挂载选项
-o use_cache=/tmp/s3fs-cache
-o parallel_count=10
-o multipart_size=64
-o max_stat_cache_size=100000
```

### Mountpoint-S3优化
```bash
# 挂载选项
--cache /tmp/mountpoint-cache
--part-size 16MB
--max-cache-size 10GB
```

## 故障排查

### 常见问题
1. **挂载失败**: 检查IAM权限和网络连接
2. **性能问题**: 调整缓存配置和并发参数
3. **健康检查失败**: 确认应用启动完成和端口监听

### 调试命令
```bash
# 检查挂载状态
mountpoint -q /mnt/s3-*

# 查看容器日志
aws logs get-log-events --log-group-name /ecs/ecs-s3-test

# 测试API连接
curl -f http://localhost:5000/health
```
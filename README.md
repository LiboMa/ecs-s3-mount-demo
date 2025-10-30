# ECS Mountpoint-S3项目

## 项目概述
在ECS容器中使用AWS官方Mountpoint-S3实现高性能S3文件系统挂载，提供Flask API接口访问S3存储桶文件。

## 项目结构
```
├── apps/app/              # Mountpoint-S3 Flask API应用
├── terraform/             # 基础设施代码 (ECS EC2)
├── scripts/              # 部署和测试脚本
├── tests/                # 测试用例
└── docs/                 # 文档
```

## 架构图
```
┌─────────────────────────────────────────────────────────────┐
│                Application Load Balancer                    │
│                         │                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              ECS EC2 Cluster                        │   │
│  │                                                     │   │
│  │  ┌─────────────────┐                               │   │
│  │  │   Flask App     │                               │   │
│  │  │ + mountpoint-s3 │                               │   │
│  │  └─────────────────┘                               │   │
│  │           │                                         │   │
│  │           ▼                                         │   │
│  │  ┌─────────────────┐                               │   │
│  │  │ /mnt/s3data     │                               │   │
│  │  │ (FUSE挂载)      │                               │   │
│  │  └─────────────────┘                               │   │
│  └─────────────────────────────────────────────────────┐   │
└─────────────────────────────────────────────────────────┘   │
                          │                                   │
                          ▼                                   │
                 ┌─────────────────┐                         │
                 │   S3 Bucket     │                         │
                 └─────────────────┘                         │
```

## 快速开始
1. **环境准备**: `./scripts/setup.sh`
2. **部署前检查**: `./scripts/pre-deploy-check.sh` (可选)
3. **部署基础设施**: `./scripts/deploy.sh`
4. **测试基本功能**: `./scripts/test-app.sh`
5. **测试读写功能**: `./scripts/test-readwrite.sh`
6. **清理资源**: `./scripts/cleanup.sh`

## 主要特性

### Mountpoint-S3优势
- 🚀 **极高性能**: 比传统方案快10-20倍
- 💚 **低资源消耗**: 内存和CPU使用更少
- 🏢 **AWS官方支持**: 官方维护和优化
- ⚡ **智能缓存**: 自适应缓存策略
- 🔧 **易于部署**: 简化的配置和管理
- 📝 **完整读写**: 支持文件创建、修改、删除操作

## API端点
- `GET /health` - 健康检查
- `GET /api/files` - 文件列表
- `POST /api/files` - 创建目录
- `GET /api/files/{path}` - 文件信息
- `DELETE /api/files/{path}` - 删除文件/目录
- `GET /api/files/{path}/content` - 读取文件内容
- `PUT /api/files/{path}/content` - 写入文件内容
- `POST /api/files/{path}/content` - 上传文件
- `GET /api/mount` - 挂载信息
- `GET /api/stats` - 统计信息

## 技术要求
- **ECS启动类型**: EC2 (支持FUSE)
- **权限**: SYS_ADMIN capability
- **网络**: VPC with public subnets
- **存储**: S3存储桶访问权限

## 文档
- [快速开始](docs/quick-start.md) - 详细部署指南
- [API文档](docs/api-documentation.md) - 完整API参考
- [故障排查](docs/troubleshooting.md) - 常见问题解决
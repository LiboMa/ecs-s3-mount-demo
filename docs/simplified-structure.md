# 简化后的项目结构

## 目录结构
```
ECS_MountingS3/
├── apps/app/              # Mountpoint-S3 Flask API应用
│   ├── Dockerfile         # 主Dockerfile
│   ├── Dockerfile.backup  # 备用Dockerfile
│   ├── app.py            # Flask应用代码
│   ├── requirements.txt  # Python依赖
│   └── entrypoint.sh     # 启动脚本
├── terraform/            # 基础设施代码
│   ├── main.tf          # 主要资源定义
│   ├── ecs.tf           # ECS相关资源
│   ├── ecs-ec2.tf       # ECS EC2配置
│   ├── variables.tf     # 变量定义
│   ├── outputs.tf       # 输出定义
│   └── terraform.tfvars # 变量值
├── scripts/             # 部署和测试脚本
│   ├── setup.sh         # 环境设置
│   ├── deploy.sh        # 部署脚本
│   ├── test-app.sh      # 应用测试
│   ├── test-readwrite.sh # 读写功能测试
│   └── cleanup.sh       # 资源清理
├── tests/               # 测试用例
└── docs/                # 文档
```

## 简化内容

### 移除的组件
- ❌ **docker目录**: 不再需要独立的测试容器
- ❌ **S3FS-FUSE应用**: 专注于Mountpoint-S3
- ❌ **S3测试任务**: 简化ECS配置
- ❌ **多ECR仓库**: 只需要一个应用仓库

### 保留的核心功能
- ✅ **Mountpoint-S3应用**: 完整的读写API
- ✅ **ECS EC2部署**: 支持FUSE挂载
- ✅ **Terraform基础设施**: 自动化部署
- ✅ **测试脚本**: 功能和性能验证

## 部署流程

### 1. 环境设置
```bash
./scripts/setup.sh
```
- 创建ECR仓库
- 构建并推送Docker镜像
- 获取VPC和子网信息
- 生成Terraform配置

### 2. 基础设施部署
```bash
./scripts/deploy.sh
```
- 部署ECS集群
- 创建应用负载均衡器
- 启动Mountpoint-S3应用

### 3. 功能测试
```bash
./scripts/test-app.sh        # 基础功能
./scripts/test-readwrite.sh  # 读写功能
```

### 4. 资源清理
```bash
./scripts/cleanup.sh
```

## 配置文件

### terraform.tfvars
```hcl
project_name = "ecs-s3-test"
aws_region = "us-west-2"
vpc_id = "vpc-xxx"
subnet_ids = ["subnet-xxx", "subnet-yyy"]
app_ecr_repository_url = "xxx.dkr.ecr.us-west-2.amazonaws.com/mountpoint-s3-app"
```

### .env文件
```bash
APP_ECR_REPOSITORY_URL=xxx.dkr.ecr.us-west-2.amazonaws.com/mountpoint-s3-app
AWS_REGION=us-west-2
VPC_ID=vpc-xxx
SUBNET_IDS=["subnet-xxx","subnet-yyy"]
```

## 优势

### 简化的架构
- 🎯 **单一焦点**: 专注于Mountpoint-S3
- 🚀 **更快部署**: 减少组件和依赖
- 🔧 **易于维护**: 更少的配置文件
- 💰 **成本优化**: 更少的AWS资源

### 保持的功能
- 📝 **完整API**: 支持所有CRUD操作
- ⚡ **高性能**: Mountpoint-S3优化
- 🔒 **安全性**: IAM角色和VPC隔离
- 📊 **监控**: CloudWatch日志和指标

这个简化版本专注于核心功能，提供了更清晰的架构和更快的部署体验。
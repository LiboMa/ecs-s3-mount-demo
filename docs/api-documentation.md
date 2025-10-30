# Flask S3挂载文件系统API文档

## 概述

这个Flask API应用通过s3fs-fuse挂载的文件系统提供对S3存储桶的访问。应用运行在ECS Fargate上，通过Application Load Balancer提供HTTP访问。

## 基础信息

- **基础URL**: `http://<load-balancer-dns>`
- **API版本**: v1
- **响应格式**: JSON
- **挂载路径**: `/mnt/s3data`

## API端点

### 1. 健康检查

**GET** `/health`

检查应用和S3挂载状态。

**响应示例:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00.000Z",
  "version": "1.0.0",
  "mount_path": "/mnt/s3data",
  "s3_mount": "mounted",
  "mount_accessible": true
}
```

### 2. 文件列表和目录操作

**GET** `/api/files` - 列出文件和目录
**POST** `/api/files` - 创建目录

列出挂载文件系统中的文件和目录，或创建新目录。

**查询参数:**
- `path` (可选): 子路径，默认为根目录
- `max_files` (可选): 最大文件数量，默认1000

**请求示例:**
```bash
curl "http://api-url/api/files?path=test_data&max_files=50"
```

**响应示例:**
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "name": "sample.txt",
        "path": "sample.txt",
        "type": "file",
        "size": 1024,
        "modified": "2024-01-01T12:00:00.000Z",
        "permissions": "644",
        "mime_type": "text/plain",
        "extension": ".txt"
      },
      {
        "name": "documents",
        "path": "documents",
        "type": "directory",
        "size": 0,
        "modified": "2024-01-01T11:00:00.000Z",
        "permissions": "755"
      }
    ],
    "count": 2,
    "path": "",
    "total_size": 1024
  },
  "mount_path": "/mnt/s3data",
  "bucket": "my-s3-bucket"
}
```

### 3. 文件信息和删除

**GET** `/api/files/<file_path>` - 获取文件信息
**DELETE** `/api/files/<file_path>` - 删除文件或目录

获取指定文件的详细信息或删除文件/目录。

**路径参数:**
- `file_path`: 文件相对路径

**请求示例:**
```bash
curl "http://api-url/api/files/sample.txt"
```

**响应示例:**
```json
{
  "success": true,
  "data": {
    "name": "sample.txt",
    "path": "sample.txt",
    "type": "file",
    "size": 1024,
    "modified": "2024-01-01T12:00:00.000Z",
    "accessed": "2024-01-01T12:30:00.000Z",
    "created": "2024-01-01T11:30:00.000Z",
    "permissions": "644",
    "mime_type": "text/plain",
    "encoding": null,
    "extension": ".txt",
    "absolute_path": "/mnt/s3data/sample.txt"
  }
}
```

### 4. 文件内容操作

**GET** `/api/files/<file_path>/content` - 读取文件内容
**PUT** `/api/files/<file_path>/content` - 写入文件内容  
**POST** `/api/files/<file_path>/content` - 上传文件

读取、写入或上传文件内容。

**路径参数:**
- `file_path`: 文件相对路径

**查询参数:**
- `download` (可选): 设为`true`时直接下载文件
- `max_size` (可选): 最大文件大小（字节），默认1MB

**请求示例:**
```bash
# 获取文本内容
curl "http://api-url/api/files/sample.txt/content"

# 下载文件
curl "http://api-url/api/files/sample.txt/content?download=true" -O
```

**文本文件响应:**
```json
{
  "success": true,
  "data": {
    "file_info": {
      "name": "sample.txt",
      "size": 1024,
      "type": "file"
    },
    "content_info": {
      "content": "文件内容...",
      "type": "text",
      "encoding": "utf-8"
    }
  }
}
```

**二进制文件响应:**
```json
{
  "success": true,
  "data": {
    "file_info": {
      "name": "image.jpg",
      "size": 102400,
      "type": "file"
    },
    "content_info": {
      "content": null,
      "type": "binary",
      "message": "二进制文件，无法显示内容"
    }
  }
}
```

### 5. 获取挂载信息

**GET** `/api/mount`

获取S3挂载状态和基本信息。

**响应示例:**
```json
{
  "success": true,
  "data": {
    "mount_path": "/mnt/s3data",
    "bucket_name": "my-s3-bucket",
    "is_mounted": true,
    "accessible": true,
    "sample_files": [
      {
        "name": "sample.txt",
        "type": "file",
        "size": 1024
      }
    ],
    "total_items": 15
  }
}
```

### 6. 获取统计信息

**GET** `/api/stats`

获取文件系统统计信息。

**查询参数:**
- `path` (可选): 统计指定路径，默认为根目录

**请求示例:**
```bash
curl "http://api-url/api/stats?path=documents"
```

**响应示例:**
```json
{
  "success": true,
  "data": {
    "total_files": 25,
    "total_directories": 5,
    "total_size": 10485760,
    "total_size_mb": 10.0,
    "file_types": {
      ".txt": 10,
      ".jpg": 8,
      ".pdf": 5,
      "no_extension": 2
    },
    "largest_file": {
      "name": "large_document.pdf",
      "path": "documents/large_document.pdf",
      "size": 5242880
    },
    "newest_file": {
      "name": "recent.txt",
      "path": "recent.txt",
      "modified": "2024-01-01T12:00:00.000Z"
    },
    "mount_path": "/mnt/s3data",
    "bucket_name": "my-s3-bucket",
    "scan_path": "/"
  }
}
```

## 错误响应

所有API在出错时返回统一格式的错误响应：

```json
{
  "success": false,
  "error": "错误类型",
  "message": "详细错误信息"
}
```

**常见HTTP状态码:**
- `200`: 成功
- `404`: 文件或路径不存在
- `413`: 文件过大
- `500`: 服务器内部错误
- `503`: 服务不可用（S3未挂载）

## 使用限制

- 单次文件列表最多返回1000个文件
- 文件内容预览限制1MB大小
- 目录统计最大扫描深度为3层
- 并发请求建议不超过20个

## 部署信息

### 环境变量
- `S3_BUCKET_NAME`: S3存储桶名称
- `S3_MOUNT_PATH`: 挂载路径（默认`/mnt/s3data`）
- `AWS_REGION`: AWS区域
- `PORT`: 应用端口（默认5000）
- `MAX_FILES`: 最大文件列表数量

### 健康检查
- **路径**: `/health`
- **间隔**: 30秒
- **超时**: 10秒
- **重试**: 3次

### 日志
应用日志通过CloudWatch Logs收集，日志组：`/ecs/ecs-s3-test`

## 示例用法

### 浏览文件系统
```bash
# 列出根目录
curl http://api-url/api/files

# 进入子目录
curl "http://api-url/api/files?path=documents"

# 获取文件信息
curl http://api-url/api/files/documents/readme.txt

# 查看文本文件内容
curl http://api-url/api/files/documents/readme.txt/content

# 下载文件
curl "http://api-url/api/files/documents/report.pdf/content?download=true" -O
```

### 监控和统计
```bash
# 检查服务状态
curl http://api-url/health

# 获取整体统计
curl http://api-url/api/stats

# 获取特定目录统计
curl "http://api-url/api/stats?path=documents"

# 查看挂载状态
curl http://api-url/api/mount
```
# 测试指南

## 测试策略

### 测试层级
1. **单元测试**: 基础文件操作功能
2. **集成测试**: S3与ECS集成验证
3. **性能测试**: 吞吐量和延迟基准
4. **压力测试**: 并发和极限场景
5. **故障测试**: 网络中断和恢复

## 测试用例设计

### 功能测试用例

#### TC001: 基础文件操作
- **目标**: 验证文件创建、读取、写入、删除功能
- **步骤**:
  1. 创建测试文件并写入内容
  2. 读取文件验证内容正确性
  3. 修改文件内容
  4. 删除文件
- **预期结果**: 所有操作成功，数据一致

#### TC002: 目录操作
- **目标**: 验证目录创建、列表、删除功能
- **步骤**:
  1. 创建多级目录结构
  2. 在目录中创建文件
  3. 列出目录内容
  4. 递归删除目录
- **预期结果**: 目录操作正常，文件层次正确

#### TC003: 大文件处理
- **目标**: 验证大文件上传下载能力
- **步骤**:
  1. 创建1GB测试文件
  2. 上传到S3挂载点
  3. 验证文件完整性
  4. 测量传输速度
- **预期结果**: 大文件传输成功，性能在预期范围

### 性能测试用例

#### TC101: 吞吐量测试
```python
def test_throughput():
    file_sizes = [1024, 10240, 102400, 1048576]  # 1KB到1MB
    for size in file_sizes:
        start_time = time.time()
        # 执行文件操作
        end_time = time.time()
        throughput = size / (end_time - start_time)
        assert throughput > expected_min_throughput[size]
```

#### TC102: 并发测试
```python
def test_concurrent_operations():
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = []
        for i in range(100):
            future = executor.submit(create_and_verify_file, f"file_{i}.txt")
            futures.append(future)
        
        # 验证所有操作成功
        for future in futures:
            assert future.result() == True
```

### 故障测试用例

#### TC201: 网络中断恢复
- **目标**: 验证网络中断后的恢复能力
- **步骤**:
  1. 开始大文件传输
  2. 模拟网络中断
  3. 恢复网络连接
  4. 验证传输继续或重试
- **预期结果**: 系统能够自动恢复或提供明确错误信息

#### TC202: S3服务异常
- **目标**: 验证S3服务异常时的处理
- **步骤**:
  1. 配置错误的S3权限
  2. 尝试文件操作
  3. 修复权限配置
  4. 重试操作
- **预期结果**: 提供清晰的错误信息，修复后正常工作

## 测试环境配置

### 本地测试环境
```bash
# 使用LocalStack模拟AWS服务
docker run -d -p 4566:4566 localstack/localstack

# 配置本地S3端点
export AWS_ENDPOINT_URL=http://localhost:4566
```

### 集成测试环境
- 使用真实AWS服务
- 独立的测试账户和资源
- 自动化资源清理

## 测试数据管理

### 测试数据集
```
test_data/
├── small_files/          # < 1MB文件
│   ├── text_files/
│   ├── binary_files/
│   └── unicode_files/
├── medium_files/         # 1-100MB文件
│   ├── documents/
│   ├── images/
│   └── archives/
└── large_files/          # > 100MB文件
    ├── videos/
    ├── databases/
    └── logs/
```

### 数据生成脚本
```python
def generate_test_data():
    # 生成不同大小和类型的测试文件
    sizes = [1024, 10240, 102400, 1048576, 10485760]
    types = ['text', 'binary', 'unicode', 'json', 'csv']
    
    for size in sizes:
        for file_type in types:
            create_test_file(size, file_type)
```

## 性能基准

### 预期性能指标
| 操作类型 | 文件大小 | 预期延迟 | 预期吞吐量 |
|---------|---------|---------|-----------|
| 读取 | < 1MB | < 500ms | > 10 MB/s |
| 写入 | < 1MB | < 1s | > 5 MB/s |
| 列表 | 1000文件 | < 2s | - |
| 删除 | 单文件 | < 200ms | - |

### 性能回归检测
```python
class PerformanceRegression:
    def __init__(self):
        self.baseline = load_baseline_metrics()
    
    def check_regression(self, current_metrics):
        for metric, value in current_metrics.items():
            baseline_value = self.baseline[metric]
            regression_threshold = baseline_value * 1.2  # 20%容忍度
            
            if value > regression_threshold:
                raise PerformanceRegressionError(
                    f"{metric} 性能回归: {value} > {regression_threshold}"
                )
```

## 自动化测试流程

### CI/CD集成
```yaml
# GitHub Actions 示例
name: ECS S3 Mount Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
      - name: Run setup
        run: ./scripts/setup.sh
      - name: Deploy infrastructure
        run: ./scripts/deploy.sh
      - name: Run tests
        run: ./scripts/test.sh
      - name: Cleanup
        run: ./scripts/cleanup.sh
        if: always()
```

### 测试报告生成
- JUnit XML格式测试结果
- 性能指标趋势图表
- 覆盖率报告
- 错误日志汇总

## 故障排查指南

### 常见问题诊断

#### 挂载失败
```bash
# 检查IAM权限
aws sts get-caller-identity
aws s3 ls s3://bucket-name

# 检查网络连接
curl -I https://s3.amazonaws.com

# 查看s3fs日志
tail -f /var/log/s3fs.log
```

#### 性能问题
```bash
# 监控系统资源
top
iostat -x 1

# 检查网络延迟
ping s3.amazonaws.com
traceroute s3.amazonaws.com

# S3访问统计
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name NumberOfObjects
```

### 调试技巧
1. 启用详细日志记录
2. 使用性能分析工具
3. 监控AWS CloudWatch指标
4. 分析网络流量模式
#!/bin/bash

set -e

echo "=== Mountpoint-S3应用测试脚本 ==="

# 检查环境文件
if [ ! -f .env ]; then
    echo "❌ 未找到.env文件，请先运行部署脚本"
    exit 1
fi

source .env

# 获取API URL
get_api_url() {
    echo "获取应用URL..."
    
    cd terraform
    API_URL=$(terraform output -raw app_url 2>/dev/null || echo "")
    cd ..
    
    if [ -z "$API_URL" ]; then
        echo "❌ 无法获取API URL，请检查Terraform部署状态"
        exit 1
    fi
    
    echo "应用URL: $API_URL"
    echo "APP_URL=$API_URL" >> .env
}

# 等待API服务启动
wait_for_api() {
    echo "等待应用服务启动..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "尝试连接应用 (${attempt}/${max_attempts})..."
        
        if curl -s -f "$API_URL/health" > /dev/null 2>&1; then
            echo "✅ 应用服务已启动"
            return 0
        fi
        
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "❌ 应用服务启动超时"
    return 1
}

# 测试健康检查
test_health() {
    echo "测试健康检查..."
    
    response=$(curl -s "$API_URL/health")
    echo "健康检查响应: $response"
    
    # 检查挂载类型
    if echo "$response" | grep -q '"mount_type":"mountpoint-s3"'; then
        echo "✅ Mountpoint-S3挂载类型确认"
    else
        echo "❌ 挂载类型不匹配"
        return 1
    fi
    
    if echo "$response" | grep -q '"status":"healthy"'; then
        echo "✅ 健康检查通过"
    else
        echo "❌ 健康检查失败"
        return 1
    fi
}

# 测试文件操作
test_file_operations() {
    echo "测试文件操作..."
    
    # 测试文件列表
    response=$(curl -s "$API_URL/api/files")
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 文件列表API正常"
        
        # 提取文件数量
        file_count=$(echo "$response" | grep -o '"count":[0-9]*' | cut -d':' -f2)
        echo "发现文件数量: $file_count"
    else
        echo "❌ 文件列表API失败"
        return 1
    fi
    
    # 测试挂载信息
    response=$(curl -s "$API_URL/api/mount")
    if echo "$response" | grep -q '"mount_path":"/mnt/s3data"'; then
        echo "✅ 挂载路径正确"
    else
        echo "❌ 挂载路径错误"
        return 1
    fi
}

# 性能测试
performance_test() {
    echo "执行性能测试..."
    
    # 测试响应时间
    start_time=$(date +%s%N)
    curl -s "$API_URL/api/files" > /dev/null
    end_time=$(date +%s%N)
    
    response_time=$(( (end_time - start_time) / 1000000 ))
    echo "文件列表响应时间: ${response_time}ms"
    
    # 记录性能数据
    echo "app_response_time_ms=$response_time" >> .env
    
    # 测试统计信息
    start_time=$(date +%s%N)
    curl -s "$API_URL/api/stats" > /dev/null
    end_time=$(date +%s%N)
    
    stats_time=$(( (end_time - start_time) / 1000000 ))
    echo "统计信息响应时间: ${stats_time}ms"
    
    echo "app_stats_time_ms=$stats_time" >> .env
    
    # 并发测试
    echo "测试并发性能..."
    concurrent_pids=()
    
    for i in {1..10}; do
        curl -s "$API_URL/api/files" > /dev/null &
        concurrent_pids+=($!)
    done
    
    # 等待所有请求完成
    for pid in "${concurrent_pids[@]}"; do
        wait $pid
    done
    
    echo "✅ 10个并发请求完成"
}

# 显示使用示例
show_examples() {
    echo ""
    echo "🎉 Mountpoint-S3应用测试完成！"
    echo ""
    echo "API使用示例:"
    echo "1. 健康检查:     curl $API_URL/health"
    echo "2. 列出文件:     curl $API_URL/api/files"
    echo "3. 挂载信息:     curl $API_URL/api/mount"
    echo "4. 统计信息:     curl $API_URL/api/stats"
    echo ""
    echo "特性: 极高性能, 低资源消耗, AWS官方支持"
}

# 主函数
main() {
    echo "开始测试Mountpoint-S3应用..."
    
    get_api_url
    wait_for_api
    test_health
    test_file_operations
    performance_test
    show_examples
}

main "$@"
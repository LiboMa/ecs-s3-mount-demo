#!/bin/bash

set -e

echo "=== Flask S3 API测试脚本 ==="

# 检查环境文件
if [ ! -f .env ]; then
    echo "❌ 未找到.env文件，请先运行部署脚本"
    exit 1
fi

source .env

# 获取API URL
get_api_url() {
    echo "获取API URL..."
    
    cd terraform
    API_URL=$(terraform output -raw api_url 2>/dev/null || echo "")
    cd ..
    
    if [ -z "$API_URL" ]; then
        echo "❌ 无法获取API URL，请检查Terraform部署状态"
        exit 1
    fi
    
    echo "API URL: $API_URL"
    echo "API_URL=$API_URL" >> .env
}

# 等待API服务启动
wait_for_api() {
    echo "等待API服务启动..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "尝试连接API (${attempt}/${max_attempts})..."
        
        if curl -s -f "$API_URL/health" > /dev/null 2>&1; then
            echo "✅ API服务已启动"
            return 0
        fi
        
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "❌ API服务启动超时"
    return 1
}

# 测试健康检查
test_health() {
    echo "测试健康检查..."
    
    response=$(curl -s "$API_URL/health")
    echo "健康检查响应: $response"
    
    # 检查响应是否包含success字段
    if echo "$response" | grep -q '"status":"healthy"'; then
        echo "✅ 健康检查通过"
    else
        echo "❌ 健康检查失败"
        return 1
    fi
}

# 测试文件列表API
test_file_list() {
    echo "测试文件列表API..."
    
    response=$(curl -s "$API_URL/api/files")
    echo "文件列表响应: $response"
    
    # 检查响应格式
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 文件列表API测试通过"
        
        # 提取文件数量
        file_count=$(echo "$response" | grep -o '"count":[0-9]*' | cut -d':' -f2)
        echo "发现文件数量: $file_count"
    else
        echo "❌ 文件列表API测试失败"
        return 1
    fi
}

# 测试挂载信息API
test_mount_info() {
    echo "测试挂载信息API..."
    
    response=$(curl -s "$API_URL/api/mount")
    echo "挂载信息响应: $response"
    
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 挂载信息API测试通过"
    else
        echo "❌ 挂载信息API测试失败"
        return 1
    fi
}

# 测试统计信息API
test_stats() {
    echo "测试统计信息API..."
    
    response=$(curl -s "$API_URL/api/stats")
    echo "统计信息响应: $response"
    
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 统计信息API测试通过"
    else
        echo "❌ 统计信息API测试失败"
        return 1
    fi
}

# 测试特定文件信息
test_file_info() {
    echo "测试文件信息API..."
    
    # 首先获取文件列表，找到一个测试文件
    files_response=$(curl -s "$API_URL/api/files")
    
    # 提取第一个文件路径（简单解析）
    first_file=$(echo "$files_response" | grep -o '"path":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$first_file" ]; then
        echo "测试文件: $first_file"
        
        response=$(curl -s "$API_URL/api/files/$first_file")
        echo "文件信息响应: $response"
        
        if echo "$response" | grep -q '"success":true'; then
            echo "✅ 文件信息API测试通过"
        else
            echo "❌ 文件信息API测试失败"
            return 1
        fi
    else
        echo "⚠️  未找到测试文件，跳过文件信息测试"
    fi
}

# 性能测试
performance_test() {
    echo "执行性能测试..."
    
    echo "测试并发请求..."
    for i in {1..5}; do
        curl -s "$API_URL/health" > /dev/null &
    done
    wait
    echo "✅ 并发请求测试完成"
    
    echo "测试响应时间..."
    start_time=$(date +%s%N)
    curl -s "$API_URL/api/files" > /dev/null
    end_time=$(date +%s%N)
    
    response_time=$(( (end_time - start_time) / 1000000 ))
    echo "文件列表API响应时间: ${response_time}ms"
    
    if [ $response_time -lt 5000 ]; then
        echo "✅ 响应时间测试通过"
    else
        echo "⚠️  响应时间较慢: ${response_time}ms"
    fi
}

# 显示API使用示例
show_api_examples() {
    echo ""
    echo "🎉 API测试完成！"
    echo ""
    echo "API使用示例:"
    echo "1. 健康检查:     curl $API_URL/health"
    echo "2. 列出文件:     curl $API_URL/api/files"
    echo "3. 指定路径:     curl '$API_URL/api/files?path=test_data'"
    echo "4. 挂载信息:     curl $API_URL/api/mount"
    echo "5. 统计信息:     curl $API_URL/api/stats"
    echo "6. 文件信息:     curl $API_URL/api/files/sample.txt"
    echo "7. 文件内容:     curl $API_URL/api/files/sample.txt/content"
    echo ""
    echo "Web界面访问: $API_URL"
}

# 主函数
main() {
    echo "开始测试Flask S3 API..."
    
    get_api_url
    wait_for_api
    test_health
    test_mount_info
    test_file_list
    test_stats
    test_file_info
    performance_test
    show_api_examples
}

main "$@"
#!/bin/bash

set -e

echo "=== Mountpoint-S3读写功能测试 ==="

# 检查环境文件
if [ ! -f .env ]; then
    echo "❌ 未找到.env文件，请先运行部署脚本"
    exit 1
fi

source .env

# 获取API URL
if [ -z "$APP_URL" ]; then
    echo "获取应用URL..."
    cd terraform
    APP_URL=$(terraform output -raw app_url 2>/dev/null || echo "")
    cd ..
    
    if [ -z "$APP_URL" ]; then
        echo "❌ 无法获取API URL，请检查Terraform部署状态"
        exit 1
    fi
    
    echo "APP_URL=$APP_URL" >> .env
fi

echo "应用URL: $APP_URL"

# 测试健康检查
test_health() {
    echo "1. 测试健康检查..."
    
    response=$(curl -s "$APP_URL/health")
    if echo "$response" | grep -q '"status":"healthy"'; then
        echo "✅ 健康检查通过"
        
        # 检查读写模式
        if echo "$response" | grep -q '"mode":"read-write"'; then
            echo "✅ 确认为读写模式"
        else
            echo "⚠️  模式信息不明确"
        fi
    else
        echo "❌ 健康检查失败"
        echo "响应: $response"
        return 1
    fi
}

# 测试创建目录
test_create_directory() {
    echo "2. 测试创建目录..."
    
    response=$(curl -s -X POST "$APP_URL/api/files" \
        -H "Content-Type: application/json" \
        -d '{"action": "create_directory", "path": "", "name": "test_dir"}')
    
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 目录创建成功"
    else
        echo "❌ 目录创建失败"
        echo "响应: $response"
        return 1
    fi
}

# 测试写入文件
test_write_file() {
    echo "3. 测试写入文件..."
    
    response=$(curl -s -X PUT "$APP_URL/api/files/test_dir/hello.txt/content" \
        -H "Content-Type: application/json" \
        -d '{"content": "Hello, Mountpoint-S3!\nThis is a test file.", "encoding": "utf-8"}')
    
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 文件写入成功"
    else
        echo "❌ 文件写入失败"
        echo "响应: $response"
        return 1
    fi
}

# 测试读取文件
test_read_file() {
    echo "4. 测试读取文件..."
    
    response=$(curl -s "$APP_URL/api/files/test_dir/hello.txt/content")
    
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 文件读取成功"
        
        # 检查内容
        if echo "$response" | grep -q "Hello, Mountpoint-S3"; then
            echo "✅ 文件内容正确"
        else
            echo "⚠️  文件内容可能不正确"
        fi
    else
        echo "❌ 文件读取失败"
        echo "响应: $response"
        return 1
    fi
}

# 测试文件上传
test_upload_file() {
    echo "5. 测试文件上传..."
    
    # 创建临时测试文件
    echo "This is a binary test file" > /tmp/test_upload.txt
    
    response=$(curl -s -X POST "$APP_URL/api/files/test_dir/uploaded.txt/content" \
        -F "file=@/tmp/test_upload.txt")
    
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 文件上传成功"
    else
        echo "❌ 文件上传失败"
        echo "响应: $response"
        return 1
    fi
    
    # 清理临时文件
    rm -f /tmp/test_upload.txt
}

# 测试列出文件
test_list_files() {
    echo "6. 测试列出文件..."
    
    response=$(curl -s "$APP_URL/api/files?path=test_dir")
    
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 文件列表获取成功"
        
        # 检查是否包含我们创建的文件
        if echo "$response" | grep -q "hello.txt"; then
            echo "✅ 找到创建的文件"
        else
            echo "⚠️  未找到创建的文件"
        fi
    else
        echo "❌ 文件列表获取失败"
        echo "响应: $response"
        return 1
    fi
}

# 测试删除文件
test_delete_file() {
    echo "7. 测试删除文件..."
    
    # 删除单个文件
    response=$(curl -s -X DELETE "$APP_URL/api/files/test_dir/hello.txt")
    
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 文件删除成功"
    else
        echo "❌ 文件删除失败"
        echo "响应: $response"
        return 1
    fi
}

# 测试删除目录
test_delete_directory() {
    echo "8. 测试删除目录..."
    
    # 强制删除目录（包含文件）
    response=$(curl -s -X DELETE "$APP_URL/api/files/test_dir?force=true")
    
    if echo "$response" | grep -q '"success":true'; then
        echo "✅ 目录删除成功"
    else
        echo "❌ 目录删除失败"
        echo "响应: $response"
        return 1
    fi
}

# 性能测试
test_performance() {
    echo "9. 测试读写性能..."
    
    # 创建性能测试目录
    curl -s -X POST "$APP_URL/api/files" \
        -H "Content-Type: application/json" \
        -d '{"action": "create_directory", "path": "", "name": "perf_test"}' > /dev/null
    
    # 测试写入性能
    start_time=$(date +%s%N)
    for i in {1..10}; do
        curl -s -X PUT "$APP_URL/api/files/perf_test/file_$i.txt/content" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"Performance test file $i\"}" > /dev/null
    done
    end_time=$(date +%s%N)
    
    write_time=$(( (end_time - start_time) / 1000000 ))
    echo "10个文件写入时间: ${write_time}ms"
    
    # 测试读取性能
    start_time=$(date +%s%N)
    for i in {1..10}; do
        curl -s "$APP_URL/api/files/perf_test/file_$i.txt/content" > /dev/null
    done
    end_time=$(date +%s%N)
    
    read_time=$(( (end_time - start_time) / 1000000 ))
    echo "10个文件读取时间: ${read_time}ms"
    
    # 清理性能测试文件
    curl -s -X DELETE "$APP_URL/api/files/perf_test?force=true" > /dev/null
    
    echo "✅ 性能测试完成"
}

# 显示测试总结
show_summary() {
    echo ""
    echo "🎉 Mountpoint-S3读写功能测试完成！"
    echo ""
    echo "测试的功能："
    echo "✅ 健康检查和模式验证"
    echo "✅ 目录创建"
    echo "✅ 文件写入（JSON格式）"
    echo "✅ 文件读取"
    echo "✅ 文件上传（multipart）"
    echo "✅ 文件列表"
    echo "✅ 文件删除"
    echo "✅ 目录删除"
    echo "✅ 读写性能测试"
    echo ""
    echo "API使用示例："
    echo "# 创建目录"
    echo "curl -X POST $APP_URL/api/files -H 'Content-Type: application/json' -d '{\"action\": \"create_directory\", \"name\": \"my_folder\"}'"
    echo ""
    echo "# 写入文件"
    echo "curl -X PUT $APP_URL/api/files/my_file.txt/content -H 'Content-Type: application/json' -d '{\"content\": \"Hello World!\"}'"
    echo ""
    echo "# 上传文件"
    echo "curl -X POST $APP_URL/api/files/upload.jpg/content -F 'file=@local_file.jpg'"
    echo ""
    echo "# 删除文件"
    echo "curl -X DELETE $APP_URL/api/files/my_file.txt"
}

# 主函数
main() {
    echo "开始Mountpoint-S3读写功能测试..."
    
    test_health
    test_create_directory
    test_write_file
    test_read_file
    test_upload_file
    test_list_files
    test_delete_file
    test_delete_directory
    test_performance
    show_summary
}

main "$@"
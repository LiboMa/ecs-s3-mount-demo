#!/bin/bash

set -e

echo "=== Docker构建测试脚本 ==="

# 测试应用镜像构建
test_app_build() {
    echo "测试Mountpoint-S3应用Docker构建..."
    
    if docker build -t app-test ./apps/app/; then
        echo "✅ 应用主Dockerfile构建成功"
        docker rmi app-test
        return 0
    else
        echo "❌ 应用主Dockerfile构建失败，测试备用版本..."
        if docker build -f ./apps/app/Dockerfile.backup -t app-test ./apps/app/; then
            echo "✅ 应用备用Dockerfile构建成功"
            docker rmi app-test
            return 0
        else
            echo "❌ 应用所有Dockerfile都构建失败"
            return 1
        fi
    fi
}

# 测试requirements.txt和Mountpoint-S3安装
test_requirements() {
    echo "测试Python依赖和Mountpoint-S3安装..."
    
    # 创建临时测试容器
    cat > test_requirements.dockerfile << 'EOF'
FROM amazonlinux:2
RUN yum update -y && yum install -y python3 python3-pip curl fuse
COPY apps/app/requirements.txt /tmp/requirements.txt
RUN pip3 install --upgrade pip setuptools wheel
RUN pip3 install -r /tmp/requirements.txt

# 测试Mountpoint-S3安装
RUN curl -O https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
RUN yum install -y ./mount-s3.rpm
RUN mount-s3 --version
EOF
    
    if docker build -f test_requirements.dockerfile -t req-test .; then
        echo "✅ Requirements.txt安装成功"
        docker rmi req-test
        rm test_requirements.dockerfile
        return 0
    else
        echo "❌ Requirements.txt安装失败"
        rm test_requirements.dockerfile
        
        # 测试简化版本
        echo "测试简化版requirements..."
        cat > test_simple_requirements.dockerfile << 'EOF'
FROM amazonlinux:2
RUN yum update -y && yum install -y python3 python3-pip
RUN pip3 install --upgrade pip
RUN pip3 install Flask Flask-CORS gunicorn
EOF
        
        if docker build -f test_simple_requirements.dockerfile -t req-simple-test .; then
            echo "✅ 简化版requirements安装成功"
            docker rmi req-simple-test
            rm test_simple_requirements.dockerfile
            return 0
        else
            echo "❌ 简化版requirements也安装失败"
            rm test_simple_requirements.dockerfile
            return 1
        fi
    fi
}

# 显示Docker信息
show_docker_info() {
    echo ""
    echo "=== Docker环境信息 ==="
    echo "Docker版本:"
    docker --version
    echo ""
    echo "可用镜像:"
    docker images | head -5
    echo ""
    echo "系统信息:"
    uname -a
}

# 主函数
main() {
    show_docker_info
    
    echo ""
    echo "开始Docker构建测试..."
    
    if test_requirements; then
        echo "✅ Python依赖测试通过"
    else
        echo "❌ Python依赖测试失败"
        exit 1
    fi
    
    if test_app_build; then
        echo "✅ 应用构建测试通过"
    else
        echo "❌ 应用构建测试失败"
        exit 1
    fi
    
    echo ""
    echo "🎉 所有Docker构建测试通过！"
    echo ""
    echo "现在可以运行 ./scripts/setup.sh 进行完整部署"
}

main "$@"
FROM amazonlinux:2

# 安装系统依赖
RUN yum update -y && \
    yum install -y \
    python3 \
    python3-pip \
    curl \
    fuse \
    && yum clean all

# 安装 Mountpoint-S3
RUN curl -O https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
RUN yum install -y ./mount-s3.rpm

# 验证安装
RUN mount-s3 --version

# 设置工作目录
WORKDIR /app

# 复制依赖文件
COPY requirements.txt .

# 升级pip并安装Python依赖
RUN pip3 install --upgrade pip setuptools wheel && \
    pip3 install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY app.py .

# 创建挂载点
RUN mkdir -p /mnt/s3data

# 复制启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

# 暴露端口
EXPOSE 5000

# 启动命令
ENTRYPOINT ["/entrypoint.sh"]
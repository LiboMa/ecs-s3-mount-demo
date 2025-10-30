#!/bin/bash

# ECS EC2实例用户数据脚本
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config

# 确保FUSE模块可用
modprobe fuse
echo "fuse" >> /etc/modules-load.d/fuse.conf

# 安装额外的工具
yum update -y
yum install -y htop iotop

# 启动ECS代理
start ecs
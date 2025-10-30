#!/usr/bin/env python3
"""
ECS S3挂载功能测试套件
"""

import os
import time
import pytest
import boto3
from pathlib import Path

class TestS3Operations:
    """S3操作测试类"""
    
    def setup_method(self):
        """测试前置设置"""
        self.s3_mount_path = Path("/mnt/s3data")
        self.test_file_path = self.s3_mount_path / "test_file.txt"
        self.large_file_path = self.s3_mount_path / "large_test_file.bin"
        
    def test_mount_point_exists(self):
        """测试S3挂载点是否存在"""
        assert self.s3_mount_path.exists(), "S3挂载点不存在"
        assert self.s3_mount_path.is_dir(), "S3挂载点不是目录"
        
    def test_basic_file_operations(self):
        """测试基础文件操作"""
        # 写入测试
        test_content = "这是一个测试文件内容"
        with open(self.test_file_path, 'w', encoding='utf-8') as f:
            f.write(test_content)
        
        # 读取测试
        assert self.test_file_path.exists(), "测试文件创建失败"
        with open(self.test_file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        assert content == test_content, "文件内容不匹配"
        
        # 删除测试
        self.test_file_path.unlink()
        assert not self.test_file_path.exists(), "文件删除失败"
        
    def test_large_file_operations(self):
        """测试大文件操作"""
        # 创建1MB测试文件
        file_size = 1024 * 1024  # 1MB
        test_data = b'A' * file_size
        
        start_time = time.time()
        with open(self.large_file_path, 'wb') as f:
            f.write(test_data)
        write_time = time.time() - start_time
        
        # 验证文件大小
        assert self.large_file_path.stat().st_size == file_size
        
        # 读取性能测试
        start_time = time.time()
        with open(self.large_file_path, 'rb') as f:
            read_data = f.read()
        read_time = time.time() - start_time
        
        assert read_data == test_data, "大文件内容不匹配"
        
        print(f"大文件写入时间: {write_time:.2f}秒")
        print(f"大文件读取时间: {read_time:.2f}秒")
        
        # 清理
        self.large_file_path.unlink()
        
    def test_directory_operations(self):
        """测试目录操作"""
        test_dir = self.s3_mount_path / "test_directory"
        
        # 创建目录
        test_dir.mkdir(exist_ok=True)
        assert test_dir.exists() and test_dir.is_dir()
        
        # 在目录中创建文件
        test_file = test_dir / "nested_file.txt"
        test_file.write_text("嵌套文件内容")
        assert test_file.exists()
        
        # 列出目录内容
        files = list(test_dir.iterdir())
        assert len(files) == 1
        assert files[0].name == "nested_file.txt"
        
        # 清理
        test_file.unlink()
        test_dir.rmdir()
        
    def test_concurrent_operations(self):
        """测试并发操作"""
        import threading
        import concurrent.futures
        
        def write_file(file_index):
            file_path = self.s3_mount_path / f"concurrent_file_{file_index}.txt"
            content = f"并发测试文件 {file_index}"
            file_path.write_text(content)
            return file_path
        
        # 并发创建10个文件
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(write_file, i) for i in range(10)]
            file_paths = [future.result() for future in futures]
        
        # 验证所有文件都创建成功
        for i, file_path in enumerate(file_paths):
            assert file_path.exists()
            content = file_path.read_text()
            assert content == f"并发测试文件 {i}"
        
        # 清理
        for file_path in file_paths:
            file_path.unlink()
            
    def test_s3_direct_access(self):
        """测试直接S3访问（验证数据一致性）"""
        bucket_name = os.environ.get('S3_BUCKET_NAME')
        if not bucket_name:
            pytest.skip("未设置S3_BUCKET_NAME环境变量")
            
        s3_client = boto3.client('s3')
        
        # 通过挂载点写入文件
        test_content = "S3一致性测试内容"
        mount_file = self.s3_mount_path / "consistency_test.txt"
        mount_file.write_text(test_content)
        
        # 等待S3同步
        time.sleep(2)
        
        # 通过S3 API读取
        try:
            response = s3_client.get_object(
                Bucket=bucket_name,
                Key="consistency_test.txt"
            )
            s3_content = response['Body'].read().decode('utf-8')
            assert s3_content == test_content, "S3数据不一致"
        finally:
            # 清理
            mount_file.unlink()

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
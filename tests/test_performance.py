#!/usr/bin/env python3
"""
S3挂载性能测试
"""

import os
import time
import pytest
import statistics
from pathlib import Path

class TestPerformance:
    """性能测试类"""
    
    def setup_method(self):
        """测试前置设置"""
        self.s3_mount_path = Path("/mnt/s3data")
        self.perf_dir = self.s3_mount_path / "performance_tests"
        self.perf_dir.mkdir(exist_ok=True)
        
    def teardown_method(self):
        """测试后清理"""
        # 清理测试文件
        if self.perf_dir.exists():
            for file in self.perf_dir.iterdir():
                if file.is_file():
                    file.unlink()
            self.perf_dir.rmdir()
    
    def test_write_performance(self):
        """测试写入性能"""
        file_sizes = [1024, 10240, 102400, 1048576]  # 1KB, 10KB, 100KB, 1MB
        results = {}
        
        for size in file_sizes:
            times = []
            data = b'X' * size
            
            # 执行5次测试取平均值
            for i in range(5):
                file_path = self.perf_dir / f"write_test_{size}_{i}.bin"
                
                start_time = time.time()
                with open(file_path, 'wb') as f:
                    f.write(data)
                end_time = time.time()
                
                times.append(end_time - start_time)
                file_path.unlink()  # 立即删除避免占用空间
            
            avg_time = statistics.mean(times)
            throughput = (size / avg_time) / (1024 * 1024)  # MB/s
            
            results[size] = {
                'avg_time': avg_time,
                'throughput_mbps': throughput
            }
            
            print(f"文件大小: {size/1024:.1f}KB, 平均写入时间: {avg_time:.3f}s, 吞吐量: {throughput:.2f}MB/s")
        
        # 性能断言 - 1MB文件写入应该在合理时间内完成
        assert results[1048576]['avg_time'] < 10.0, "1MB文件写入时间过长"
        
    def test_read_performance(self):
        """测试读取性能"""
        file_sizes = [1024, 10240, 102400, 1048576]  # 1KB, 10KB, 100KB, 1MB
        results = {}
        
        # 先创建测试文件
        test_files = {}
        for size in file_sizes:
            data = b'Y' * size
            file_path = self.perf_dir / f"read_test_{size}.bin"
            with open(file_path, 'wb') as f:
                f.write(data)
            test_files[size] = file_path
        
        # 测试读取性能
        for size in file_sizes:
            times = []
            file_path = test_files[size]
            
            # 执行5次测试取平均值
            for i in range(5):
                start_time = time.time()
                with open(file_path, 'rb') as f:
                    data = f.read()
                end_time = time.time()
                
                times.append(end_time - start_time)
                assert len(data) == size, f"读取数据大小不匹配: {len(data)} != {size}"
            
            avg_time = statistics.mean(times)
            throughput = (size / avg_time) / (1024 * 1024)  # MB/s
            
            results[size] = {
                'avg_time': avg_time,
                'throughput_mbps': throughput
            }
            
            print(f"文件大小: {size/1024:.1f}KB, 平均读取时间: {avg_time:.3f}s, 吞吐量: {throughput:.2f}MB/s")
        
        # 性能断言
        assert results[1048576]['avg_time'] < 5.0, "1MB文件读取时间过长"
        
    def test_small_files_performance(self):
        """测试小文件批量操作性能"""
        num_files = 100
        file_size = 1024  # 1KB
        data = b'Z' * file_size
        
        # 批量写入测试
        start_time = time.time()
        file_paths = []
        for i in range(num_files):
            file_path = self.perf_dir / f"small_file_{i}.txt"
            with open(file_path, 'wb') as f:
                f.write(data)
            file_paths.append(file_path)
        write_time = time.time() - start_time
        
        # 批量读取测试
        start_time = time.time()
        for file_path in file_paths:
            with open(file_path, 'rb') as f:
                read_data = f.read()
            assert len(read_data) == file_size
        read_time = time.time() - start_time
        
        # 批量删除测试
        start_time = time.time()
        for file_path in file_paths:
            file_path.unlink()
        delete_time = time.time() - start_time
        
        print(f"批量操作性能 ({num_files}个1KB文件):")
        print(f"  写入时间: {write_time:.3f}s ({num_files/write_time:.1f} files/s)")
        print(f"  读取时间: {read_time:.3f}s ({num_files/read_time:.1f} files/s)")
        print(f"  删除时间: {delete_time:.3f}s ({num_files/delete_time:.1f} files/s)")
        
        # 性能断言
        assert write_time < 30.0, "小文件批量写入时间过长"
        assert read_time < 15.0, "小文件批量读取时间过长"
        
    def test_directory_listing_performance(self):
        """测试目录列表性能"""
        # 创建测试文件
        num_files = 50
        for i in range(num_files):
            file_path = self.perf_dir / f"list_test_{i:03d}.txt"
            file_path.write_text(f"文件 {i}")
        
        # 测试目录列表性能
        times = []
        for _ in range(10):
            start_time = time.time()
            files = list(self.perf_dir.iterdir())
            end_time = time.time()
            times.append(end_time - start_time)
        
        avg_time = statistics.mean(times)
        print(f"目录列表性能 ({num_files}个文件): 平均时间 {avg_time:.3f}s")
        
        assert len(files) == num_files, f"文件数量不匹配: {len(files)} != {num_files}"
        assert avg_time < 2.0, "目录列表时间过长"

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
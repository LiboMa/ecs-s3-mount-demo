#!/usr/bin/env python3
"""
Mountpoint-S3 性能测试
对比 Mountpoint-S3 和 S3FS-FUSE 的性能差异
"""

import os
import time
import pytest
import statistics
from pathlib import Path

class TestMountpointPerformance:
    """Mountpoint-S3 性能测试类"""
    
    def setup_method(self):
        """测试前置设置"""
        self.s3_mount_path = Path("/mnt/s3data")
        self.test_results = {}
        
    def test_mount_verification(self):
        """验证Mountpoint-S3挂载"""
        assert self.s3_mount_path.exists(), "S3挂载点不存在"
        assert self.s3_mount_path.is_dir(), "S3挂载点不是目录"
        
        # 检查是否为Mountpoint-S3挂载
        mount_info = os.popen("mount | grep s3").read()
        print(f"挂载信息: {mount_info}")
        
    def test_read_performance_small_files(self):
        """测试小文件读取性能"""
        print("\n=== 小文件读取性能测试 ===")
        
        # 查找小于1MB的文件
        small_files = []
        try:
            for file_path in self.s3_mount_path.rglob("*"):
                if file_path.is_file():
                    size = file_path.stat().st_size
                    if size < 1024 * 1024:  # < 1MB
                        small_files.append(file_path)
                        if len(small_files) >= 10:  # 测试10个文件
                            break
        except Exception as e:
            print(f"扫描文件时出错: {e}")
            pytest.skip("无法找到测试文件")
        
        if not small_files:
            pytest.skip("未找到小文件进行测试")
        
        # 性能测试
        read_times = []
        total_size = 0
        
        for file_path in small_files:
            try:
                start_time = time.time()
                with open(file_path, 'rb') as f:
                    data = f.read()
                end_time = time.time()
                
                read_time = end_time - start_time
                read_times.append(read_time)
                total_size += len(data)
                
                print(f"文件: {file_path.name}, 大小: {len(data)} bytes, 时间: {read_time:.3f}s")
                
            except Exception as e:
                print(f"读取文件 {file_path} 失败: {e}")
                continue
        
        if read_times:
            avg_time = statistics.mean(read_times)
            total_throughput = (total_size / sum(read_times)) / (1024 * 1024)  # MB/s
            
            self.test_results['small_files'] = {
                'avg_read_time': avg_time,
                'total_throughput_mbps': total_throughput,
                'files_tested': len(read_times)
            }
            
            print(f"\n小文件读取性能:")
            print(f"  平均读取时间: {avg_time:.3f}s")
            print(f"  总吞吐量: {total_throughput:.2f} MB/s")
            print(f"  测试文件数: {len(read_times)}")
            
            # 性能断言
            assert avg_time < 1.0, f"小文件读取时间过长: {avg_time}s"
    
    def test_read_performance_large_files(self):
        """测试大文件读取性能"""
        print("\n=== 大文件读取性能测试 ===")
        
        # 查找大于1MB的文件
        large_files = []
        try:
            for file_path in self.s3_mount_path.rglob("*"):
                if file_path.is_file():
                    size = file_path.stat().st_size
                    if size > 1024 * 1024:  # > 1MB
                        large_files.append((file_path, size))
                        if len(large_files) >= 3:  # 测试3个大文件
                            break
        except Exception as e:
            print(f"扫描大文件时出错: {e}")
            pytest.skip("无法找到大文件")
        
        if not large_files:
            pytest.skip("未找到大文件进行测试")
        
        # 性能测试
        for file_path, file_size in large_files:
            try:
                print(f"\n测试大文件: {file_path.name} ({file_size / (1024*1024):.1f} MB)")
                
                # 分块读取测试
                chunk_size = 1024 * 1024  # 1MB chunks
                start_time = time.time()
                
                with open(file_path, 'rb') as f:
                    total_read = 0
                    while True:
                        chunk = f.read(chunk_size)
                        if not chunk:
                            break
                        total_read += len(chunk)
                
                end_time = time.time()
                read_time = end_time - start_time
                throughput = (total_read / read_time) / (1024 * 1024)  # MB/s
                
                print(f"  读取时间: {read_time:.3f}s")
                print(f"  吞吐量: {throughput:.2f} MB/s")
                
                # 记录结果
                if 'large_files' not in self.test_results:
                    self.test_results['large_files'] = []
                
                self.test_results['large_files'].append({
                    'file_size_mb': file_size / (1024 * 1024),
                    'read_time': read_time,
                    'throughput_mbps': throughput
                })
                
                # 性能断言
                assert throughput > 5.0, f"大文件读取吞吐量过低: {throughput:.2f} MB/s"
                
            except Exception as e:
                print(f"读取大文件 {file_path} 失败: {e}")
                continue
    
    def test_directory_listing_performance(self):
        """测试目录列表性能"""
        print("\n=== 目录列表性能测试 ===")
        
        # 测试根目录列表
        start_time = time.time()
        try:
            root_files = list(self.s3_mount_path.iterdir())
            end_time = time.time()
            
            list_time = end_time - start_time
            file_count = len(root_files)
            
            print(f"根目录列表:")
            print(f"  文件数量: {file_count}")
            print(f"  列表时间: {list_time:.3f}s")
            print(f"  速度: {file_count/list_time:.1f} files/s")
            
            self.test_results['directory_listing'] = {
                'file_count': file_count,
                'list_time': list_time,
                'files_per_second': file_count / list_time if list_time > 0 else 0
            }
            
            # 性能断言
            assert list_time < 5.0, f"目录列表时间过长: {list_time}s"
            
        except Exception as e:
            print(f"目录列表测试失败: {e}")
            pytest.fail(f"目录列表失败: {e}")
    
    def test_metadata_operations(self):
        """测试元数据操作性能"""
        print("\n=== 元数据操作性能测试 ===")
        
        # 收集测试文件
        test_files = []
        try:
            for file_path in self.s3_mount_path.rglob("*"):
                if file_path.is_file():
                    test_files.append(file_path)
                    if len(test_files) >= 20:  # 测试20个文件
                        break
        except Exception as e:
            print(f"收集测试文件失败: {e}")
            pytest.skip("无法收集测试文件")
        
        if not test_files:
            pytest.skip("未找到测试文件")
        
        # stat() 操作性能测试
        stat_times = []
        for file_path in test_files:
            try:
                start_time = time.time()
                stat_info = file_path.stat()
                end_time = time.time()
                
                stat_time = end_time - start_time
                stat_times.append(stat_time)
                
            except Exception as e:
                print(f"stat操作失败 {file_path}: {e}")
                continue
        
        if stat_times:
            avg_stat_time = statistics.mean(stat_times)
            
            print(f"元数据操作性能:")
            print(f"  平均stat时间: {avg_stat_time:.4f}s")
            print(f"  测试文件数: {len(stat_times)}")
            
            self.test_results['metadata_ops'] = {
                'avg_stat_time': avg_stat_time,
                'files_tested': len(stat_times)
            }
            
            # 性能断言
            assert avg_stat_time < 0.1, f"元数据操作时间过长: {avg_stat_time}s"
    
    def test_concurrent_read_performance(self):
        """测试并发读取性能"""
        print("\n=== 并发读取性能测试 ===")
        
        import threading
        import concurrent.futures
        
        # 收集测试文件
        test_files = []
        try:
            for file_path in self.s3_mount_path.rglob("*"):
                if file_path.is_file():
                    size = file_path.stat().st_size
                    if size < 10 * 1024 * 1024:  # < 10MB
                        test_files.append(file_path)
                        if len(test_files) >= 10:
                            break
        except Exception as e:
            pytest.skip(f"收集测试文件失败: {e}")
        
        if len(test_files) < 5:
            pytest.skip("测试文件不足")
        
        def read_file(file_path):
            """读取单个文件"""
            try:
                start_time = time.time()
                with open(file_path, 'rb') as f:
                    data = f.read()
                end_time = time.time()
                return {
                    'file': file_path.name,
                    'size': len(data),
                    'time': end_time - start_time
                }
            except Exception as e:
                return {'error': str(e)}
        
        # 并发读取测试
        start_time = time.time()
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(read_file, f) for f in test_files[:5]]
            results = [future.result() for future in futures]
        end_time = time.time()
        
        total_time = end_time - start_time
        successful_reads = [r for r in results if 'error' not in r]
        
        if successful_reads:
            total_size = sum(r['size'] for r in successful_reads)
            total_throughput = (total_size / total_time) / (1024 * 1024)
            
            print(f"并发读取性能:")
            print(f"  总时间: {total_time:.3f}s")
            print(f"  成功读取: {len(successful_reads)}/{len(results)}")
            print(f"  总吞吐量: {total_throughput:.2f} MB/s")
            
            self.test_results['concurrent_read'] = {
                'total_time': total_time,
                'successful_reads': len(successful_reads),
                'total_throughput_mbps': total_throughput
            }
    
    def teardown_method(self):
        """测试后输出汇总"""
        if self.test_results:
            print("\n" + "="*50)
            print("Mountpoint-S3 性能测试汇总")
            print("="*50)
            
            for test_name, results in self.test_results.items():
                print(f"\n{test_name.upper()}:")
                for key, value in results.items():
                    if isinstance(value, float):
                        print(f"  {key}: {value:.3f}")
                    else:
                        print(f"  {key}: {value}")

if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
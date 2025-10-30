#!/usr/bin/env python3
"""
Flask S3挂载文件系统API应用
通过s3fs-fuse挂载的本地路径访问S3文件
"""

import os
import json
import logging
import mimetypes
from datetime import datetime
from pathlib import Path
from flask import Flask, jsonify, request, send_file
from flask_cors import CORS

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 创建Flask应用
app = Flask(__name__)
CORS(app)  # 启用跨域支持

# 配置
S3_MOUNT_PATH = os.environ.get('S3_MOUNT_PATH', '/mnt/s3data')
S3_BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')
MAX_FILES = int(os.environ.get('MAX_FILES', '1000'))
MOUNT_TYPE = os.environ.get('MOUNT_TYPE', 'mountpoint-s3')

# 验证挂载路径
mount_path = Path(S3_MOUNT_PATH)
if mount_path.exists():
    logger.info(f"S3挂载路径验证成功: {S3_MOUNT_PATH}")
else:
    logger.warning(f"S3挂载路径不存在: {S3_MOUNT_PATH}")
    mount_path = None

class FileSystemService:
    """挂载文件系统服务类"""
    
    def __init__(self, mount_path):
        self.mount_path = Path(mount_path)
    
    def is_mounted(self):
        """检查是否已挂载"""
        return self.mount_path.exists() and self.mount_path.is_dir()
    
    def list_files(self, subpath='', max_files=1000):
        """列出文件和目录"""
        try:
            target_path = self.mount_path / subpath if subpath else self.mount_path
            
            if not target_path.exists():
                raise FileNotFoundError(f"路径不存在: {subpath}")
            
            if not target_path.is_dir():
                raise NotADirectoryError(f"不是目录: {subpath}")
            
            items = []
            count = 0
            
            # 遍历目录内容
            for item in target_path.iterdir():
                if count >= max_files:
                    break
                
                try:
                    stat = item.stat()
                    relative_path = item.relative_to(self.mount_path)
                    
                    item_info = {
                        'name': item.name,
                        'path': str(relative_path),
                        'type': 'directory' if item.is_dir() else 'file',
                        'size': stat.st_size if item.is_file() else 0,
                        'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                        'permissions': oct(stat.st_mode)[-3:],
                    }
                    
                    # 添加文件类型信息
                    if item.is_file():
                        mime_type, _ = mimetypes.guess_type(str(item))
                        item_info['mime_type'] = mime_type or 'application/octet-stream'
                        item_info['extension'] = item.suffix.lower()
                    
                    items.append(item_info)
                    count += 1
                    
                except (OSError, PermissionError) as e:
                    logger.warning(f"无法访问文件 {item}: {e}")
                    continue
            
            # 按类型和名称排序
            items.sort(key=lambda x: (x['type'] == 'file', x['name'].lower()))
            
            return {
                'items': items,
                'count': len(items),
                'path': subpath,
                'total_size': sum(item['size'] for item in items if item['type'] == 'file')
            }
            
        except Exception as e:
            logger.error(f"列出文件失败: {e}")
            raise
    
    def get_file_info(self, file_path):
        """获取文件详细信息"""
        try:
            target_file = self.mount_path / file_path
            
            if not target_file.exists():
                return None
            
            stat = target_file.stat()
            mime_type, encoding = mimetypes.guess_type(str(target_file))
            
            return {
                'name': target_file.name,
                'path': file_path,
                'type': 'directory' if target_file.is_dir() else 'file',
                'size': stat.st_size,
                'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                'accessed': datetime.fromtimestamp(stat.st_atime).isoformat(),
                'created': datetime.fromtimestamp(stat.st_ctime).isoformat(),
                'permissions': oct(stat.st_mode)[-3:],
                'mime_type': mime_type or 'application/octet-stream',
                'encoding': encoding,
                'extension': target_file.suffix.lower(),
                'absolute_path': str(target_file)
            }
            
        except Exception as e:
            logger.error(f"获取文件信息失败: {e}")
            raise
    
    def read_file_content(self, file_path, max_size=1024*1024):
        """读取文件内容（限制大小）"""
        try:
            target_file = self.mount_path / file_path
            
            if not target_file.exists() or not target_file.is_file():
                return None
            
            file_size = target_file.stat().st_size
            if file_size > max_size:
                raise ValueError(f"文件过大: {file_size} bytes > {max_size} bytes")
            
            # 尝试以文本方式读取
            try:
                with open(target_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                return {'content': content, 'type': 'text', 'encoding': 'utf-8'}
            except UnicodeDecodeError:
                # 如果不是文本文件，返回二进制信息
                return {
                    'content': None, 
                    'type': 'binary', 
                    'message': '二进制文件，无法显示内容'
                }
                
        except Exception as e:
            logger.error(f"读取文件内容失败: {e}")
            raise
    
    def get_directory_stats(self, subpath=''):
        """获取目录统计信息"""
        try:
            target_path = self.mount_path / subpath if subpath else self.mount_path
            
            if not target_path.exists() or not target_path.is_dir():
                return None
            
            stats = {
                'total_files': 0,
                'total_directories': 0,
                'total_size': 0,
                'file_types': {},
                'largest_file': None,
                'newest_file': None
            }
            
            newest_time = 0
            largest_size = 0
            
            # 递归统计（限制深度避免性能问题）
            def scan_directory(path, depth=0, max_depth=3):
                if depth > max_depth:
                    return
                
                try:
                    for item in path.iterdir():
                        if item.is_file():
                            stat = item.stat()
                            stats['total_files'] += 1
                            stats['total_size'] += stat.st_size
                            
                            # 文件类型统计
                            ext = item.suffix.lower() or 'no_extension'
                            stats['file_types'][ext] = stats['file_types'].get(ext, 0) + 1
                            
                            # 最大文件
                            nonlocal largest_size
                            if stat.st_size > largest_size:
                                largest_size = stat.st_size
                                stats['largest_file'] = {
                                    'name': item.name,
                                    'path': str(item.relative_to(self.mount_path)),
                                    'size': stat.st_size
                                }
                            
                            # 最新文件
                            nonlocal newest_time
                            if stat.st_mtime > newest_time:
                                newest_time = stat.st_mtime
                                stats['newest_file'] = {
                                    'name': item.name,
                                    'path': str(item.relative_to(self.mount_path)),
                                    'modified': datetime.fromtimestamp(stat.st_mtime).isoformat()
                                }
                                
                        elif item.is_dir():
                            stats['total_directories'] += 1
                            scan_directory(item, depth + 1, max_depth)
                            
                except PermissionError:
                    pass
            
            scan_directory(target_path)
            return stats
            
        except Exception as e:
            logger.error(f"获取目录统计失败: {e}")
            raise

# 检查是否使用S3 API回退模式
USE_S3_API = os.environ.get('USE_S3_API', 'false').lower() == 'true'

# 初始化文件系统服务
fs_service = None
if USE_S3_API:
    logger.info("使用S3 API回退模式")
    # 这里可以初始化S3客户端作为回退
    # 暂时创建一个标记文件系统服务
    if mount_path:
        mount_path.mkdir(exist_ok=True)
        fs_service = FileSystemService(S3_MOUNT_PATH)
        logger.info(f"S3 API回退模式初始化成功")
elif mount_path and mount_path.exists():
    fs_service = FileSystemService(S3_MOUNT_PATH)
    logger.info(f"文件系统服务初始化成功，挂载路径: {S3_MOUNT_PATH}")
else:
    logger.error(f"文件系统服务初始化失败，挂载路径不存在: {S3_MOUNT_PATH}")

@app.route('/health', methods=['GET'])
def health_check():
    """健康检查端点"""
    status = {
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'version': '1.0.0',
        'mount_path': S3_MOUNT_PATH,
        'mount_type': MOUNT_TYPE,
        'mode': 'read-write',
        'description': 'S3文件系统完整访问服务'
    }
    
    # 检查S3挂载状态
    if fs_service:
        try:
            is_mounted = fs_service.is_mounted()
            status['s3_mount'] = 'mounted' if is_mounted else 'not_mounted'
            
            if is_mounted:
                # 尝试列出根目录验证可访问性
                result = fs_service.list_files(max_files=1)
                status['mount_accessible'] = True
            else:
                status['mount_accessible'] = False
                return jsonify(status), 503
                
        except Exception as e:
            status['s3_mount'] = 'error'
            status['mount_error'] = str(e)
            return jsonify(status), 503
    else:
        status['s3_mount'] = 'not_configured'
        return jsonify(status), 503
    
    return jsonify(status)

@app.route('/api/files', methods=['GET', 'POST'])
def handle_files():
    """处理文件列表 - 列出文件、创建目录"""
    if not fs_service:
        return jsonify({
            'error': 'S3文件系统未挂载',
            'message': '请检查S3挂载状态'
        }), 500
    
    if request.method == 'GET':
        # 列出文件
        try:
            # 获取查询参数
            path = request.args.get('path', '')
            max_files = min(int(request.args.get('max_files', MAX_FILES)), MAX_FILES)
            
            logger.info(f"列出文件请求: path='{path}', max_files={max_files}")
            
            # 获取文件列表
            result = fs_service.list_files(subpath=path, max_files=max_files)
            
            response = {
                'success': True,
                'data': result,
                'mount_path': S3_MOUNT_PATH,
                'bucket': S3_BUCKET_NAME
            }
            
            return jsonify(response)
            
        except FileNotFoundError as e:
            return jsonify({
                'success': False,
                'error': '路径不存在',
                'message': str(e)
            }), 404
        except Exception as e:
            logger.error(f"列出文件失败: {e}")
            return jsonify({
                'success': False,
                'error': str(e),
                'message': '获取文件列表失败'
            }), 500
    
    elif request.method == 'POST':
        # 创建目录或上传文件
        try:
            data = request.get_json()
            
            if not data:
                return jsonify({
                    'success': False,
                    'error': '缺少请求数据'
                }), 400
            
            action = data.get('action')
            path = data.get('path', '')
            
            if action == 'create_directory':
                # 创建目录
                dir_name = data.get('name')
                if not dir_name:
                    return jsonify({
                        'success': False,
                        'error': '缺少目录名称'
                    }), 400
                
                target_dir = Path(S3_MOUNT_PATH) / path / dir_name
                target_dir.mkdir(parents=True, exist_ok=True)
                
                return jsonify({
                    'success': True,
                    'message': f'目录创建成功: {dir_name}',
                    'path': str(Path(path) / dir_name)
                })
            
            else:
                return jsonify({
                    'success': False,
                    'error': f'不支持的操作: {action}'
                }), 400
                
        except Exception as e:
            logger.error(f"文件操作失败: {e}")
            return jsonify({
                'success': False,
                'error': str(e),
                'message': '文件操作失败'
            }), 500

@app.route('/api/files/<path:file_path>', methods=['GET', 'DELETE'])
def handle_file_info(file_path):
    """处理文件信息 - 获取信息、删除文件"""
    if not fs_service:
        return jsonify({
            'error': 'S3文件系统未挂载'
        }), 500
    
    if request.method == 'GET':
        # 获取文件信息
        try:
            logger.info(f"获取文件信息: {file_path}")
            
            file_info = fs_service.get_file_info(file_path)
            
            if file_info is None:
                return jsonify({
                    'success': False,
                    'error': '文件不存在',
                    'path': file_path
                }), 404
            
            return jsonify({
                'success': True,
                'data': file_info
            })
            
        except Exception as e:
            logger.error(f"获取文件信息失败: {e}")
            return jsonify({
                'success': False,
                'error': str(e),
                'message': '获取文件信息失败'
            }), 500
    
    elif request.method == 'DELETE':
        # 删除文件或目录
        try:
            logger.info(f"删除文件: {file_path}")
            
            target_path = Path(S3_MOUNT_PATH) / file_path
            
            if not target_path.exists():
                return jsonify({
                    'success': False,
                    'error': '文件或目录不存在',
                    'path': file_path
                }), 404
            
            if target_path.is_file():
                target_path.unlink()
                message = f"文件删除成功: {file_path}"
            elif target_path.is_dir():
                # 检查是否为空目录
                if any(target_path.iterdir()):
                    # 非空目录，需要确认
                    force = request.args.get('force', 'false').lower() == 'true'
                    if not force:
                        return jsonify({
                            'success': False,
                            'error': '目录非空，请使用force=true参数强制删除',
                            'path': file_path
                        }), 400
                    
                    # 递归删除
                    import shutil
                    shutil.rmtree(target_path)
                    message = f"目录及其内容删除成功: {file_path}"
                else:
                    target_path.rmdir()
                    message = f"空目录删除成功: {file_path}"
            
            return jsonify({
                'success': True,
                'message': message,
                'path': file_path
            })
            
        except Exception as e:
            logger.error(f"删除文件失败: {e}")
            return jsonify({
                'success': False,
                'error': str(e),
                'message': '删除文件失败'
            }), 500

@app.route('/api/files/<path:file_path>/content', methods=['GET', 'PUT', 'POST'])
def handle_file_content(file_path):
    """处理文件内容 - 读取、写入、上传"""
    if not fs_service:
        return jsonify({
            'error': 'S3文件系统未挂载'
        }), 500
    
    if request.method == 'GET':
        # 读取文件内容
        try:
            logger.info(f"获取文件内容: {file_path}")
            
            # 检查文件是否存在
            file_info = fs_service.get_file_info(file_path)
            if file_info is None:
                return jsonify({
                    'success': False,
                    'error': '文件不存在',
                    'path': file_path
                }), 404
            
            if file_info['type'] != 'file':
                return jsonify({
                    'success': False,
                    'error': '不是文件',
                    'path': file_path
                }), 400
            
            # 获取查询参数
            download = request.args.get('download', 'false').lower() == 'true'
            max_size = int(request.args.get('max_size', 1024*1024))  # 默认1MB
            
            if download:
                # 直接下载文件
                target_file = Path(S3_MOUNT_PATH) / file_path
                return send_file(
                    target_file,
                    as_attachment=True,
                    download_name=file_info['name']
                )
            else:
                # 返回文件内容（文本文件）
                content_info = fs_service.read_file_content(file_path, max_size)
                
                return jsonify({
                    'success': True,
                    'data': {
                        'file_info': file_info,
                        'content_info': content_info
                    }
                })
            
        except ValueError as e:
            return jsonify({
                'success': False,
                'error': str(e),
                'message': '文件过大，请使用下载方式'
            }), 413
        except Exception as e:
            logger.error(f"获取文件内容失败: {e}")
            return jsonify({
                'success': False,
                'error': str(e),
                'message': '获取文件内容失败'
            }), 500
    
    elif request.method in ['PUT', 'POST']:
        # 写入文件内容
        try:
            logger.info(f"写入文件内容: {file_path}")
            
            target_file = Path(S3_MOUNT_PATH) / file_path
            
            # 确保目录存在
            target_file.parent.mkdir(parents=True, exist_ok=True)
            
            # 获取内容
            if request.is_json:
                # JSON格式的文本内容
                data = request.get_json()
                content = data.get('content', '')
                encoding = data.get('encoding', 'utf-8')
                
                with open(target_file, 'w', encoding=encoding) as f:
                    f.write(content)
                    
                message = f"文本文件写入成功: {len(content)} 字符"
                
            else:
                # 二进制内容或文件上传
                if 'file' in request.files:
                    # 文件上传
                    uploaded_file = request.files['file']
                    uploaded_file.save(target_file)
                    message = f"文件上传成功: {uploaded_file.filename}"
                else:
                    # 原始数据
                    content = request.get_data()
                    with open(target_file, 'wb') as f:
                        f.write(content)
                    message = f"二进制文件写入成功: {len(content)} 字节"
            
            # 获取写入后的文件信息
            file_info = fs_service.get_file_info(file_path)
            
            return jsonify({
                'success': True,
                'message': message,
                'data': file_info
            })
            
        except Exception as e:
            logger.error(f"写入文件失败: {e}")
            return jsonify({
                'success': False,
                'error': str(e),
                'message': '写入文件失败'
            }), 500

@app.route('/api/mount', methods=['GET'])
def get_mount_info():
    """获取挂载信息"""
    if not fs_service:
        return jsonify({
            'error': 'S3文件系统未挂载'
        }), 500
    
    try:
        mount_info = {
            'mount_path': S3_MOUNT_PATH,
            'bucket_name': S3_BUCKET_NAME,
            'is_mounted': fs_service.is_mounted(),
            'accessible': True
        }
        
        # 尝试获取根目录信息
        try:
            root_info = fs_service.list_files(max_files=5)
            mount_info['sample_files'] = root_info['items'][:5]
            mount_info['total_items'] = root_info['count']
        except Exception as e:
            mount_info['accessible'] = False
            mount_info['error'] = str(e)
        
        return jsonify({
            'success': True,
            'data': mount_info
        })
        
    except Exception as e:
        logger.error(f"获取挂载信息失败: {e}")
        return jsonify({
            'success': False,
            'error': str(e),
            'message': '获取挂载信息失败'
        }), 500

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """获取文件系统统计信息"""
    if not fs_service:
        return jsonify({
            'error': 'S3文件系统未挂载'
        }), 500
    
    try:
        # 获取查询参数
        path = request.args.get('path', '')
        
        logger.info(f"获取统计信息: path='{path}'")
        
        # 获取目录统计
        stats = fs_service.get_directory_stats(path)
        
        if stats is None:
            return jsonify({
                'success': False,
                'error': '路径不存在或不是目录',
                'path': path
            }), 404
        
        # 添加额外信息
        stats['mount_path'] = S3_MOUNT_PATH
        stats['bucket_name'] = S3_BUCKET_NAME
        stats['scan_path'] = path or '/'
        stats['total_size_mb'] = round(stats['total_size'] / (1024 * 1024), 2)
        
        return jsonify({
            'success': True,
            'data': stats
        })
        
    except Exception as e:
        logger.error(f"获取统计信息失败: {e}")
        return jsonify({
            'success': False,
            'error': str(e),
            'message': '获取统计信息失败'
        }), 500

@app.errorhandler(404)
def not_found(error):
    """404错误处理"""
    return jsonify({
        'success': False,
        'error': '接口不存在',
        'message': '请检查API路径'
    }), 404

@app.errorhandler(500)
def internal_error(error):
    """500错误处理"""
    return jsonify({
        'success': False,
        'error': '服务器内部错误',
        'message': '请稍后重试'
    }), 500

if __name__ == '__main__':
    # 检查必要的环境变量和挂载路径
    if not S3_BUCKET_NAME:
        logger.error("未设置S3_BUCKET_NAME环境变量")
        exit(1)
    
    if not fs_service:
        logger.error(f"S3文件系统未挂载: {S3_MOUNT_PATH}")
        exit(1)
    
    # 启动应用
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
    
    logger.info(f"启动Flask应用，端口: {port}, 调试模式: {debug}")
    logger.info(f"S3挂载路径: {S3_MOUNT_PATH}")
    logger.info(f"S3存储桶: {S3_BUCKET_NAME}")
    
    app.run(host='0.0.0.0', port=port, debug=debug)
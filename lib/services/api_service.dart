import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'storage_service.dart';
import '../models/book.dart';

class ApiService {
  final StorageService _storageService;
  late final Dio _dio;

  ApiService(this._storageService) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));

    // 添加拦截器：自动注入 Bearer Token 和 伪装 User-Agent
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // 动态读取并设置 User-Agent (核心功能：防止被服主判定为非法客户端)
        final userAgent = _storageService.getCustomUA();
        options.headers['User-Agent'] = userAgent;

        // 注入 Token 认证信息
        final token = _storageService.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        developer.log('Request to: ${options.uri}', name: 'ApiService');
        developer.log('Headers: ${options.headers}', name: 'ApiService');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        developer.log('Response from ${response.requestOptions.uri}: ${response.statusCode}', name: 'ApiService');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        developer.log('Dio Error on ${e.requestOptions.uri}: ${e.message}', error: e, name: 'ApiService');
        return handler.next(e);
      },
    ));
  }

  // 格式化服务器 URL
  String _formatUrl(String url) {
    var formatted = url.trim();
    if (formatted.endsWith('/')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }

  // 登录 Audiobookshelf
  Future<Map<String, dynamic>?> login(String rawUrl, String username, String password) async {
    try {
      final baseUrl = _formatUrl(rawUrl);
      final loginEndpoint = '$baseUrl/api/login';
      
      developer.log('Attempting login to: $loginEndpoint', name: 'ApiService');

      final response = await _dio.post(
        loginEndpoint,
        data: {
          'username': username,
          'password': password,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        
        // 兼容不同版本的 ABS API 响应结构
        String? token;
        String? userId;
        
        if (data.containsKey('token')) {
          token = data['token'] as String?;
        }
        if (data['user'] != null && data['user'] is Map) {
          final userMap = data['user'] as Map<String, dynamic>;
          token ??= userMap['token'] as String?;
          userId = userMap['id'] as String?;
        }

        if (token != null) {
          // 保存凭据
          await _storageService.setServerUrl(baseUrl);
          await _storageService.setUsername(username);
          await _storageService.setToken(token);
          if (userId != null) {
            await _storageService.setUserId(userId);
          }
          return {
            'success': true,
            'token': token,
            'userId': userId,
            'url': baseUrl,
          };
        }
      }
      return {'success': false, 'message': '登录失败，未收到有效 Token'};
    } catch (e) {
      developer.log('Login failed with exception', error: e, name: 'ApiService');
      String errMsg = '连接服务器失败，请检查网络或地址';
      if (e is DioException) {
        if (e.response != null) {
          errMsg = '服务器错误 (${e.response?.statusCode}): ${e.response?.data?['message'] ?? e.response?.statusMessage}';
        } else {
          errMsg = '连接超时或无法触达服务器';
        }
      }
      return {'success': false, 'message': errMsg};
    }
  }

  // 获取书库列表
  Future<List<Map<String, dynamic>>> getLibraries() async {
    try {
      final baseUrl = _storageService.getServerUrl();
      if (baseUrl == null) throw Exception('Server URL not configured');

      final response = await _dio.get('$baseUrl/api/libraries');
      if (response.statusCode == 200 && response.data != null) {
        // 返回的可能是一个包含 libraries 列表的对象，或直接是一个数组
        final data = response.data;
        if (data is List) {
          return List<Map<String, dynamic>>.from(data.map((item) => item as Map<String, dynamic>));
        } else if (data is Map && data['libraries'] != null) {
          final libs = data['libraries'] as List;
          return List<Map<String, dynamic>>.from(libs.map((item) => item as Map<String, dynamic>));
        }
      }
      return [];
    } catch (e) {
      developer.log('Get libraries failed', error: e, name: 'ApiService');
      return [];
    }
  }

  // 获取书库中的有声书列表
  Future<List<Book>> getLibraryItems(String libraryId) async {
    try {
      final baseUrl = _storageService.getServerUrl();
      if (baseUrl == null) throw Exception('Server URL not configured');

      final response = await _dio.get('$baseUrl/api/libraries/$libraryId/items');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        List<dynamic> items = [];
        if (data is List) {
          items = data;
        } else if (data is Map && data['results'] != null) {
          items = data['results'] as List;
        }

        final books = <Book>[];
        for (final item in items) {
          if (item['media'] != null && item['media']['metadata'] != null) {
            books.add(Book.fromJson(item as Map<String, dynamic>));
          }
        }
        return books;
      }
      return [];
    } catch (e) {
      developer.log('Get library items failed', error: e, name: 'ApiService');
      return [];
    }
  }

  // 获取书籍完整详情
  Future<Book?> getBookDetails(String bookId) async {
    try {
      final baseUrl = _storageService.getServerUrl();
      if (baseUrl == null) throw Exception('Server URL not configured');

      final response = await _dio.get('$baseUrl/api/items/$bookId');
      if (response.statusCode == 200 && response.data != null) {
        return Book.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      developer.log('Get book details failed', error: e, name: 'ApiService');
      return null;
    }
  }

  // 启动播放会话 (核心播放初始化)
  Future<Map<String, dynamic>?> startPlaySession(String bookId) async {
    try {
      final baseUrl = _storageService.getServerUrl();
      if (baseUrl == null) throw Exception('Server URL not configured');

      developer.log('Starting play session for book: $bookId', name: 'ApiService');
      final response = await _dio.post(
        '$baseUrl/api/items/$bookId/play',
        data: {
          'deviceInfo': {
            'clientName': 'ListenShell',
            'deviceId': 'listenshell_windows_pc',
            'clientVersion': '1.0.0',
          },
          'forceDirectPlay': true,
          'supportedMimeTypes': ['audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/flac', 'audio/ogg'],
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      developer.log('Start play session failed', error: e, name: 'ApiService');
      return null;
    }
  }

  // 同步播放进度至 Audiobookshelf 服务端
  Future<void> syncPlaybackProgress({
    required String bookId,
    required String sessionId,
    required double currentTime,
    required double timeListened,
    required double duration,
    required double playbackRate,
  }) async {
    try {
      final baseUrl = _storageService.getServerUrl();
      if (baseUrl == null) throw Exception('Server URL not configured');

      await _dio.post(
        '$baseUrl/api/items/$bookId/session/$sessionId',
        data: {
          'currentTime': currentTime,
          'timeListened': timeListened,
          'duration': duration,
          'playbackRate': playbackRate,
        },
      );
      developer.log(
        'Synced progress: current=${currentTime.toStringAsFixed(1)}s, listened=${timeListened.toStringAsFixed(1)}s, rate=${playbackRate}x',
        name: 'ApiService',
      );
    } catch (e) {
      // 吞掉同步进度的错误，不打扰核心播放流程，但记录日志
      developer.log('Sync playback progress failed', error: e, name: 'ApiService');
    }
  }
}

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:xml/xml.dart';
import 'storage_service.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import 'log_collector.dart';

class ApiService {
  final StorageService _storageService;
  late final Dio _dio;

  bool get isRssMode => _storageService.getToken() == 'rss_token';
  bool get isSubsonicMode => _storageService.getToken()?.startsWith('subsonic_') == true;
  String? get currentUrl => _storageService.getServerUrl();

  ApiService(this._storageService) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));

    setupProxy(); // 初始化全局代理

    // 添加拦截器：自动注入 Bearer Token 和 伪装 User-Agent
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // 动态读取并设置 User-Agent (核心功能：防止被服主判定为非法客户端)
        final userAgent = _storageService.getCustomUA();
        options.headers['User-Agent'] = userAgent;

        if (isSubsonicMode) {
          // Subsonic 模式：动态添加 query 鉴权参数，不使用 Authorization header
          final token = _storageService.getToken() ?? '';
          if (token.startsWith('subsonic_')) {
            final password = token.substring(9);
            final username = _storageService.getUsername() ?? '';
            final params = _buildSubsonicParams(username, password);
            options.queryParameters.addAll(params);
          }
        } else {
          // 注入 ABS Token 认证信息
          final token = _storageService.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
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

  // 执行 Subsonic / Navidrome 登录鉴权
  Future<Map<String, dynamic>?> loginSubsonic(String rawUrl, String username, String password) async {
    try {
      final baseUrl = _formatUrl(rawUrl);
      final params = _buildSubsonicParams(username, password);
      
      LogCollector.instance.log('Attempting Subsonic ping to: $baseUrl/rest/ping.view, u=$username');

      final response = await _dio.get(
        '$baseUrl/rest/ping.view',
        queryParameters: params,
      );

      LogCollector.instance.log('Subsonic ping response: status=${response.statusCode}, body=${response.data}');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final responseObj = data['subsonic-response'] as Map<String, dynamic>?;
        if (responseObj != null && responseObj['status'] == 'ok') {
          // 校验成功，写入本地持久化。密码带上 "subsonic_" 前缀存入 token 字段
          await _storageService.setServerUrl(baseUrl);
          await _storageService.setUsername(username);
          await _storageService.setToken('subsonic_$password');
          LogCollector.instance.log('Subsonic login successful for u=$username');
          return {
            'success': true,
            'url': baseUrl,
          };
        } else {
          LogCollector.instance.log('Subsonic ping status was not ok: $responseObj');
        }
      }
      return {'success': false, 'message': '验证失败：请检查账号密码或服务器版本'};
    } catch (e) {
      LogCollector.instance.log('Ping Subsonic failed', error: e);
      String errMsg = '连接服务器失败，请检查地址是否正确';
      if (e is DioException) {
        if (e.response != null) {
          errMsg = '服务器错误 (${e.response?.statusCode})';
        } else {
          errMsg = '连接超时或无法触达服务器';
        }
      }
      return {'success': false, 'message': errMsg};
    }
  }

  // 生成 Subsonic API 安全验证参数
  Map<String, String> _buildSubsonicParams(String username, String password) {
    final salt = DateTime.now().millisecondsSinceEpoch.toString().substring(0, 6);
    final bytes = utf8.encode(password + salt);
    final digest = md5.convert(bytes);
    final token = digest.toString();
    
    return {
      'u': username,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'listenshell',
      'f': 'json',
    };
  }

  // 拼接得到一个用于直连播放或图片的 subsonic query 字符串
  String buildSubsonicQueryString() {
    final token = _storageService.getToken() ?? '';
    if (token.startsWith('subsonic_')) {
      final password = token.substring(9);
      final username = _storageService.getUsername() ?? '';
      final params = _buildSubsonicParams(username, password);
      return params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    }
    return '';
  }

  // 获取书库列表
  Future<List<Map<String, dynamic>>> getLibraries() async {
    try {
      final baseUrl = _storageService.getServerUrl();
      if (baseUrl == null) throw Exception('Server URL not configured');

      if (isSubsonicMode) {
        return [
          {'id': 'subsonic_library', 'name': 'Navidrome 音乐库'}
        ];
      }

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

      if (isSubsonicMode) {
        LogCollector.instance.log('Subsonic mode: fetching album list via getAlbumList2.view');
        // 请求 Subsonic 专辑列表做为书籍列表 (使用 newest 兼容所有 subsonic 音乐服)
        final response = await _dio.get('$baseUrl/rest/getAlbumList2.view?type=newest&size=500');
        LogCollector.instance.log('Subsonic getAlbumList2 response: status=${response.statusCode}, body=${response.data}');
        if (response.statusCode == 200 && response.data != null) {
          final responseObj = response.data['subsonic-response'] as Map<String, dynamic>?;
          if (responseObj != null && responseObj['status'] == 'ok') {
            final albumList = responseObj['albumList2'] as Map<String, dynamic>?;
            if (albumList != null && albumList['album'] != null) {
              final albums = albumList['album'] as List<dynamic>;
              final queryStr = buildSubsonicQueryString();
              final books = <Book>[];
              for (final a in albums) {
                if (a is Map<String, dynamic>) {
                  final albumId = a['id'] as String;
                  final coverArtId = a['coverArt'] as String?;
                  final coverUrl = coverArtId != null 
                      ? '$baseUrl/rest/getCoverArt.view?id=$coverArtId&$queryStr'
                      : null;
                  books.add(Book(
                    id: albumId,
                    title: a['name'] as String? ?? '未知专辑',
                    author: a['artist'] as String? ?? '未知歌手',
                    narrator: 'Navidrome',
                    description: '音轨数: ${a['songCount'] ?? '未知'}',
                    duration: (a['duration'] as num?)?.toDouble() ?? 0.0,
                    chapters: [],
                    tracks: [],
                    isRss: true, // 标记为 isRss == true (多文件模式) 完美继承 RSS 播放流底座
                    rssCoverUrl: coverUrl,
                  ));
                }
              }
              LogCollector.instance.log('Successfully parsed Subsonic albums count: ${books.length}');
              return books;
            } else {
              LogCollector.instance.log('Subsonic albumList2 or album element is null: $albumList');
            }
          } else {
            LogCollector.instance.log('Subsonic response status not ok or responseObj is null: $responseObj');
          }
        }
        return [];
      }

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

      if (isRssMode) {
        return await parseRssFeed(baseUrl);
      }

      if (isSubsonicMode) {
        LogCollector.instance.log('Subsonic mode: fetching album details for id=$bookId');
        // 请求 Subsonic 专辑歌曲详情并转化为 Chapter 列表
        final response = await _dio.get('$baseUrl/rest/getAlbum.view?id=$bookId');
        LogCollector.instance.log('Subsonic getAlbum response: status=${response.statusCode}, body=${response.data}');
        if (response.statusCode == 200 && response.data != null) {
          final responseObj = response.data['subsonic-response'] as Map<String, dynamic>?;
          if (responseObj != null && responseObj['status'] == 'ok') {
            final albumObj = responseObj['album'] as Map<String, dynamic>?;
            if (albumObj != null) {
              final songList = albumObj['song'] as List<dynamic>? ?? [];
              final queryStr = buildSubsonicQueryString();
              final chaptersList = <Chapter>[];
              double currentStart = 0.0;
              
              for (var i = 0; i < songList.length; i++) {
                final s = songList[i];
                if (s is Map<String, dynamic>) {
                  final songId = s['id'] as String;
                  final songTitle = s['title'] as String? ?? '音轨 ${i + 1}';
                  final dur = (s['duration'] as num?)?.toDouble() ?? 300.0;
                  final audioUrl = '$baseUrl/rest/stream.view?id=$songId&$queryStr';
                  
                  chaptersList.add(Chapter(
                    id: i,
                    title: songTitle,
                    start: currentStart,
                    end: currentStart + dur,
                    audioUrl: audioUrl,
                  ));
                  currentStart += dur;
                }
              }

              final coverArtId = albumObj['coverArt'] as String?;
              final coverUrl = coverArtId != null 
                  ? '$baseUrl/rest/getCoverArt.view?id=$coverArtId&$queryStr'
                  : null;

              LogCollector.instance.log('Successfully parsed Subsonic album details, songs count: ${chaptersList.length}');

              return Book(
                id: bookId,
                title: albumObj['name'] as String? ?? '未知专辑',
                author: albumObj['artist'] as String? ?? '未知歌手',
                narrator: 'Navidrome',
                description: '包含 ${songList.length} 个音轨章节。',
                duration: currentStart,
                chapters: chaptersList,
                tracks: [],
                isRss: true,
                rssCoverUrl: coverUrl,
              );
            } else {
              LogCollector.instance.log('Subsonic album element is null: $albumObj');
            }
          } else {
            LogCollector.instance.log('Subsonic response status not ok or responseObj is null: $responseObj');
          }
        }
        return null;
      }

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

  // 免密 RSS 订阅源 XML 数据流解析逻辑
  Future<Book?> parseRssFeed(String feedUrl) async {
    try {
      LogCollector.instance.log('Starting RSS Feed fetch from: $feedUrl');
      
      // 显式指定以纯文本格式拉取 XML，防止 Dio 底层错误解析
      final response = await _dio.get(
        feedUrl,
        options: Options(responseType: ResponseType.plain),
      );
      
      LogCollector.instance.log('RSS fetch response status: ${response.statusCode}, payload length: ${response.data?.toString().length ?? 0}');

      if (response.statusCode != 200 || response.data == null) {
        throw Exception('获取 RSS 失败，状态码: ${response.statusCode}');
      }

      final xmlString = response.data.toString();
      final document = XmlDocument.parse(xmlString);
      
      // findAllElements 会在任意层级查找 channel
      final channel = document.findAllElements('channel').firstOrNull;
      if (channel == null) {
        throw Exception('未找到有效的 channel 节点');
      }

      // 提取标题和简介 (使用 localName 兼容所有命名空间)
      final title = channel.findElements('title').firstOrNull?.innerText ?? '未知有声书';
      final description = channel.findElements('description').firstOrNull?.innerText ?? '免密 RSS 订阅播客';
      
      // 提取封面图
      String? coverUrl;
      final imageNode = channel.findElements('image').firstOrNull;
      if (imageNode != null) {
        coverUrl = imageNode.findElements('url').firstOrNull?.innerText;
      }
      
      // itunes:image 兼容模糊查找
      if (coverUrl == null || coverUrl.isEmpty) {
        XmlElement? itunesImage;
        for (final e in channel.descendants.whereType<XmlElement>()) {
          if (e.name.local == 'image' && e.getAttribute('href') != null) {
            itunesImage = e;
            break;
          }
        }
        coverUrl = itunesImage?.getAttribute('href');
      }

      final items = channel.findAllElements('item'); // 确保能拿到所有的 item 节点
      final chaptersList = <Chapter>[];
      double currentStart = 0.0;

      int idx = 0;
      for (final item in items) {
        final itemTitle = item.findElements('title').firstOrNull?.innerText ?? '第 ${idx + 1} 章节';
        
        final enclosure = item.findElements('enclosure').firstOrNull;
        if (enclosure == null) continue;
        
        final audioUrl = enclosure.getAttribute('url');
        if (audioUrl == null || audioUrl.isEmpty) continue;

        // 提取时长 (兼容 itunes:duration，模糊匹配 local 为 duration 的子元素)
        XmlElement? durationNode;
        for (final e in item.descendants.whereType<XmlElement>()) {
          if (e.name.local == 'duration') {
            durationNode = e;
            break;
          }
        }
        final durationStr = durationNode?.innerText ?? '00:00';
        final durationSeconds = _parseDuration(durationStr);

        chaptersList.add(Chapter(
          id: idx,
          title: itemTitle,
          start: currentStart,
          end: currentStart + durationSeconds,
          audioUrl: audioUrl,
        ));
        
        currentStart += durationSeconds;
        idx++;
      }

      if (chaptersList.isEmpty) {
        throw Exception('解析完成，但未提取到任何章节音轨');
      }

      LogCollector.instance.log('Successfully parsed RSS book: $title, chapters count: ${chaptersList.length}');

      return Book(
        id: 'rss_${feedUrl.hashCode}',
        title: title,
        author: 'RSS 播客源',
        narrator: '免密收听',
        description: description,
        duration: currentStart,
        chapters: chaptersList,
        tracks: [], // RSS 模式下直接通过 Chapter.audioUrl 播放
        isRss: true,
        rssCoverUrl: coverUrl,
      );
    } catch (e, stack) {
      LogCollector.instance.log('Parse RSS Feed failed', error: e, stackTrace: stack);
      return null;
    }
  }

  // 辅助方法：解析 RSS 时长格式（如 16:21 或 01:15:32 等）
  double _parseDuration(String durationStr) {
    try {
      if (durationStr.contains(':')) {
        final parts = durationStr.split(':');
        if (parts.length == 2) {
          final m = int.parse(parts[0]);
          final s = int.parse(parts[1]);
          return (m * 60 + s).toDouble();
        } else if (parts.length == 3) {
          final h = int.parse(parts[0]);
          final m = int.parse(parts[1]);
          final s = int.parse(parts[2]);
          return (h * 3600 + m * 60 + s).toDouble();
        }
      }
      return double.parse(durationStr);
    } catch (_) {
      return 300.0; // 解析失败默认设为 5 分钟
    }
  }

  // 动态构建和应用 HTTP 全局代理配置
  void setupProxy() {
    try {
      final proxy = _storageService.getHttpProxy();
      if (proxy != null && proxy.isNotEmpty) {
        var cleanProxy = proxy.trim();
        // 自动填充 http 协议头
        if (!cleanProxy.startsWith('http://') && !cleanProxy.startsWith('https://')) {
          cleanProxy = 'http://$cleanProxy';
        }
        final cleanAddr = cleanProxy.replaceFirst('http://', '').replaceFirst('https://', '');
        
        _dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () {
            final client = HttpClient();
            client.findProxy = (uri) => "PROXY $cleanAddr";
            client.badCertificateCallback = (cert, host, port) => true;
            return client;
          },
        );
        LogCollector.instance.log('HTTP 代理应用成功: $cleanProxy');
      } else {
        _dio.httpClientAdapter = IOHttpClientAdapter();
        LogCollector.instance.log('已禁用 HTTP 全局代理');
      }
    } catch (e) {
      LogCollector.instance.log('应用 HTTP 代理发生错误', error: e);
    }
  }
}

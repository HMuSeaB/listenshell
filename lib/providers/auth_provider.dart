import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final StorageService _storageService;

  bool _isInitialized = false;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider(this._apiService, this._storageService);

  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  String? get serverUrl => _storageService.getServerUrl();
  String? get username => _storageService.getUsername();
  String get customUA => _storageService.getCustomUA();
  bool get isSubsonicMode => _apiService.isSubsonicMode;
  bool get isRssMode => _apiService.isRssMode;

  // 初始化，尝试使用本地保存的 Token 自动登录
  Future<void> tryAutoLogin() async {
    _isLoading = true;
    notifyListeners();

    final token = _storageService.getToken();
    final url = _storageService.getServerUrl();
    final user = _storageService.getUsername();

    if (token != null && token.isNotEmpty && url != null && user != null) {
      // 简单起见，如果本地有凭证即代表已认证。在真实应用中，可以发起一个快速的获取库请求来验证 Token 有效性。
      _isAuthenticated = true;
    } else {
      _isAuthenticated = false;
    }

    _isInitialized = true;
    _isLoading = false;
    notifyListeners();
  }

  // 执行登录
  Future<bool> login(String url, String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.login(url, username, password);
    _isLoading = false;

    if (result != null && result['success'] == true) {
      _isAuthenticated = true;
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _isAuthenticated = false;
      _errorMessage = result?['message'] ?? '登录失败';
      notifyListeners();
      return false;
    }
  }

  // 供外部直接以 RSS 模式“登录”
  Future<bool> loginRss(String url) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final book = await _apiService.parseRssFeed(url);
      _isLoading = false;

      if (book != null) {
        // 解析通过，判定连接成功，写入本地持久化
        await _storageService.setServerUrl(url);
        await _storageService.setUsername("RSS免密订阅");
        await _storageService.setToken("rss_token"); // 写入虚拟 Token 以供自动登录鉴权使用
        
        _isAuthenticated = true;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _isAuthenticated = false;
        _errorMessage = '无法解析此 RSS 订阅源，请检查链接';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _isAuthenticated = false;
      _errorMessage = '连接失败: 地址未响应或格式有误';
      notifyListeners();
      return false;
    }
  }

  // 执行 Subsonic / Navidrome 登录
  Future<bool> loginSubsonic(String url, String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.loginSubsonic(url, username, password);
    _isLoading = false;

    if (result != null && result['success'] == true) {
      _isAuthenticated = true;
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _isAuthenticated = false;
      _errorMessage = result?['message'] ?? '登录验证失败';
      notifyListeners();
      return false;
    }
  }

  // 保存自定义 User-Agent
  Future<void> updateCustomUA(String ua) async {
    await _storageService.setCustomUA(ua);
    notifyListeners();
  }

  // 登出
  Future<void> logout() async {
    await _storageService.clearAuthData();
    _isAuthenticated = false;
    notifyListeners();
  }
}

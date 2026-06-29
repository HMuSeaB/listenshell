import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// App 全局视图状态枚举
enum AppView {
  serverSelector, // 服务器选择中枢页
  login,          // 新建/编辑连接登录页
  home,           // 主书架页
}

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final StorageService _storageService;

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _errorMessage;
  AppView _currentView = AppView.serverSelector;

  AuthProvider(this._apiService, this._storageService);

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  AppView get currentView => _currentView;

  // 保留旧接口兼容性：home 态即为已认证
  bool get isAuthenticated => _currentView == AppView.home;

  String? get serverUrl => _storageService.getServerUrl();
  String? get username => _storageService.getUsername();
  String get customUA => _storageService.getCustomUA();
  bool get isSubsonicMode => _apiService.isSubsonicMode;
  bool get isRssMode => _apiService.isRssMode;

  // 初始化，判断该进入哪个视图
  Future<void> tryAutoLogin() async {
    _isLoading = true;
    notifyListeners();

    final profiles = _storageService.getServerProfiles();

    if (profiles.isNotEmpty) {
      // 有已保存的 Profile → 进入服务器选择中枢
      _currentView = AppView.serverSelector;
    } else {
      // 无 Profile → 直接进入登录页
      _currentView = AppView.login;
    }

    _isInitialized = true;
    _isLoading = false;
    notifyListeners();
  }

  // 切换到服务器选择中枢页（不清除 Profile 数据）
  void switchToServerSelector() {
    _currentView = AppView.serverSelector;
    _errorMessage = null;
    notifyListeners();
  }

  // 切换到登录页面（用于添加新服务器）
  void switchToLogin() {
    _currentView = AppView.login;
    _errorMessage = null;
    notifyListeners();
  }

  // 从已保存的 Profile 恢复凭据并自动连接
  Future<bool> connectToProfile(Map<String, dynamic> profile) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final type = profile['type'] as int? ?? 0;
      final url = profile['url'] as String? ?? '';
      final user = profile['username'] as String? ?? '';
      final pass = profile['password'] as String? ?? '';
      // customUAPreset 仅在 LoginView 中使用，此处不需要
      final customUA = profile['customUA'] as String? ?? '';
      final httpProxy = profile['httpProxy'] as String? ?? '';

      // 先应用 UA 和代理设置
      if (customUA.isNotEmpty) {
        await _storageService.setCustomUA(customUA);
      }
      if (httpProxy.isNotEmpty) {
        await _storageService.setHttpProxy(httpProxy);
        _apiService.setupProxy();
      }

      bool success;
      if (type == 1) {
        // RSS 模式
        success = await _loginRssInternal(url);
      } else if (type == 2) {
        // Subsonic / Navidrome 模式
        success = await _loginSubsonicInternal(url, user, pass);
      } else {
        // ABS 标准模式
        success = await _loginAbsInternal(url, user, pass);
      }

      if (success) {
        // 记录活跃的 Profile ID
        final profileId = profile['id'] as String? ?? '';
        await _storageService.setActiveProfileId(profileId);

        _currentView = AppView.home;
        _errorMessage = null;
      } else {
        _errorMessage ??= '连接失败';
      }

      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _isLoading = false;
      _errorMessage = '连接异常: $e';
      notifyListeners();
      return false;
    }
  }

  // 内部 ABS 登录逻辑
  Future<bool> _loginAbsInternal(String url, String username, String password) async {
    final result = await _apiService.login(url, username, password);
    if (result != null && result['success'] == true) {
      return true;
    } else {
      _errorMessage = result?['message'] ?? '登录失败';
      return false;
    }
  }

  // 内部 RSS 登录逻辑
  Future<bool> _loginRssInternal(String url) async {
    try {
      final book = await _apiService.parseRssFeed(url);
      if (book != null) {
        await _storageService.setServerUrl(url);
        await _storageService.setUsername("RSS免密订阅");
        await _storageService.setToken("rss_token");
        return true;
      } else {
        _errorMessage = '无法解析此 RSS 订阅源，请检查链接';
        return false;
      }
    } catch (e) {
      _errorMessage = '连接失败: 地址未响应或格式有误';
      return false;
    }
  }

  // 内部 Subsonic 登录逻辑
  Future<bool> _loginSubsonicInternal(String url, String username, String password) async {
    final result = await _apiService.loginSubsonic(url, username, password);
    if (result != null && result['success'] == true) {
      return true;
    } else {
      _errorMessage = result?['message'] ?? '登录验证失败';
      return false;
    }
  }

  // 执行登录（供 LoginView 直接调用）
  Future<bool> login(String url, String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final success = await _loginAbsInternal(url, username, password);
    _isLoading = false;

    if (success) {
      _currentView = AppView.home;
      _errorMessage = null;
    }
    notifyListeners();
    return success;
  }

  // 供外部直接以 RSS 模式"登录"
  Future<bool> loginRss(String url) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final success = await _loginRssInternal(url);
    _isLoading = false;

    if (success) {
      _currentView = AppView.home;
      _errorMessage = null;
    }
    notifyListeners();
    return success;
  }

  // 执行 Subsonic / Navidrome 登录
  Future<bool> loginSubsonic(String url, String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final success = await _loginSubsonicInternal(url, username, password);
    _isLoading = false;

    if (success) {
      _currentView = AppView.home;
      _errorMessage = null;
    }
    notifyListeners();
    return success;
  }

  // 保存自定义 User-Agent
  Future<void> updateCustomUA(String ua) async {
    await _storageService.setCustomUA(ua);
    notifyListeners();
  }

  // 获取当前的代理
  String? get httpProxy => _storageService.getHttpProxy();

  // 保存和更新 HTTP 全局代理，并实时生效
  Future<void> updateHttpProxy(String proxy) async {
    await _storageService.setHttpProxy(proxy);
    _apiService.setupProxy();
    notifyListeners();
  }

  // 登出（清除当前连接的认证数据，但不清除 Profile 历史列表）
  Future<void> logout() async {
    await _storageService.clearAuthData();
    _currentView = AppView.serverSelector;
    notifyListeners();
  }
}

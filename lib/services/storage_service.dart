import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // 获取服务器地址
  String? getServerUrl() => _prefs.getString(AppConstants.keyServerUrl);
  Future<bool> setServerUrl(String value) => _prefs.setString(AppConstants.keyServerUrl, value);

  // 获取用户名
  String? getUsername() => _prefs.getString(AppConstants.keyUsername);
  Future<bool> setUsername(String value) => _prefs.setString(AppConstants.keyUsername, value);

  // 获取 Token
  String? getToken() => _prefs.getString(AppConstants.keyToken);
  Future<bool> setToken(String value) => _prefs.setString(AppConstants.keyToken, value);

  // 获取 User ID
  String? getUserId() => _prefs.getString(AppConstants.keyUserId);
  Future<bool> setUserId(String value) => _prefs.setString(AppConstants.keyUserId, value);

  // 获取自定义 User-Agent，若为空则返回默认伪装的 UA
  String getCustomUA() => _prefs.getString(AppConstants.keyCustomUA) ?? AppConstants.defaultUserAgent;
  Future<bool> setCustomUA(String value) => _prefs.setString(AppConstants.keyCustomUA, value);

  // 清理登录敏感数据
  Future<void> clearAuthData() async {
    await _prefs.remove(AppConstants.keyToken);
    await _prefs.remove(AppConstants.keyUserId);
  }

  // 保存和读取某本书的播放绝对进度
  double getBookProgress(String bookId) => _prefs.getDouble('progress_$bookId') ?? 0.0;
  Future<bool> setBookProgress(String bookId, double value) => _prefs.setDouble('progress_$bookId', value);

  // 获取和设置 HTTP 代理
  String? getHttpProxy() => _prefs.getString('http_proxy');
  Future<bool> setHttpProxy(String value) => _prefs.setString('http_proxy', value);

  // 获取服务器历史记录
  List<Map<String, dynamic>> getServerProfiles() {
    final raw = _prefs.getString('server_profiles');
    if (raw == null) return [];
    try {
      final list = json.decode(raw) as List<dynamic>;
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  // 保存服务器历史记录
  Future<bool> saveServerProfiles(List<Map<String, dynamic>> profiles) {
    final raw = json.encode(profiles);
    return _prefs.setString('server_profiles', raw);
  }

  // 获取上次活跃的 Profile ID
  String? getActiveProfileId() => _prefs.getString('active_profile_id');
  Future<bool> setActiveProfileId(String value) => _prefs.setString('active_profile_id', value);
}

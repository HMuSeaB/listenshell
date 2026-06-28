import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'constants/app_constants.dart';
import 'providers/auth_provider.dart';
import 'providers/library_provider.dart';
import 'providers/playback_provider.dart';
import 'services/api_service.dart';
import 'services/audio_service.dart';
import 'services/storage_service.dart';
import 'views/home_view.dart';
import 'views/login_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化 media_kit 播放引擎 (必须首要初始化)
  MediaKit.ensureInitialized();

  // 2. 初始化 window_manager 桌面窗口管理器
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(1024, 768),
    center: true,
    title: AppConstants.appName,
    titleBarStyle: TitleBarStyle.normal,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 3. 初始化本地持久化存储
  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);

  // 4. 初始化底层及网络服务
  final apiService = ApiService(storageService);
  final audioService = AudioService();

  runApp(
    MultiProvider(
      providers: [
        // 基础存储服务注入
        Provider<StorageService>.value(value: storageService),
        // 核心 API 与播放服务注入
        Provider<ApiService>.value(value: apiService),
        Provider<AudioService>.value(value: audioService),
        // 状态管理 Provider 注入
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(apiService, storageService)..tryAutoLogin(),
        ),
        ChangeNotifierProvider<LibraryProvider>(
          create: (_) => LibraryProvider(apiService),
        ),
        ChangeNotifierProvider<PlaybackProvider>(
          create: (_) => PlaybackProvider(apiService, audioService, storageService),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // 启用高质感的 Material 3 墨绿/青色深色主题 (最适合夜晚有声书收听环境)
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121817),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF182221),
          selectedIconTheme: IconThemeData(color: Colors.tealAccent),
          unselectedIconTheme: IconThemeData(color: Colors.white70),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// 自动登录与权限认证路由网关
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // 1. 若本地存储中的 Token 仍在读取校验中，显示全屏渐变加载
    if (!auth.isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在恢复本地连接配置...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    // 2. 根据登录认证状态分流界面
    if (auth.isAuthenticated) {
      return const HomeView();
    } else {
      return const LoginView();
    }
  }
}

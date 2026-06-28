import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/playback_provider.dart';
import '../services/storage_service.dart';
import '../models/book.dart';
import 'book_detail_view.dart';
import 'player_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _navIndex = 0; // 0: 书架, 1: 设置
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 自动加载书库数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().fetchLibraries();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playbackProvider = context.watch<PlaybackProvider>();

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // 1. 左侧导航栏 (向 Hills Player 原生体验看齐)
                NavigationRail(
                  selectedIndex: _navIndex,
                  onDestinationSelected: (index) {
                    if (index == 2) {
                      // 退出登录
                      _showLogoutDialog();
                    } else {
                      setState(() {
                        _navIndex = index;
                      });
                    }
                  },
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Icon(Icons.headphones, size: 36),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.library_books),
                      selectedIcon: Icon(Icons.library_books_rounded),
                      label: Text('书架'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings),
                      selectedIcon: Icon(Icons.settings_applications),
                      label: Text('设置'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.logout, color: Colors.redAccent),
                      label: Text('登出', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),

                // 2. 右侧主体页面
                Expanded(
                  child: _navIndex == 0 ? _buildLibraryView() : _buildSettingsView(),
                ),
              ],
            ),
          ),
          
          // 3. 底部迷你播放器栏
          if (playbackProvider.currentBook != null)
            const MiniPlayerBar(),
        ],
      ),
    );
  }

  // 构建书架视图
  Widget _buildLibraryView() {
    final libProvider = context.watch<LibraryProvider>();
    final authProvider = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final storageService = context.read<StorageService>();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部栏：书库切换与搜索
          Row(
            children: [
              // 书库下拉列表
              if (libProvider.libraries.isNotEmpty)
                DropdownButton<Map<String, dynamic>>(
                  value: libProvider.selectedLibrary,
                  icon: const Icon(Icons.arrow_drop_down),
                  underline: Container(height: 0),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  onChanged: (Map<String, dynamic>? newLib) {
                    if (newLib != null) {
                      libProvider.selectLibrary(newLib);
                    }
                  },
                  items: libProvider.libraries.map<DropdownMenuItem<Map<String, dynamic>>>((lib) {
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: lib,
                      child: Text(lib['name'] as String? ?? '书库'),
                    );
                  }).toList(),
                )
              else
                Text(
                  '我的有声书',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              const Spacer(),

              // 搜索框
              SizedBox(
                width: 300,
                height: 44,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索书名/作者/朗读者...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              libProvider.search('');
                            },
                          )
                        : null,
                  ),
                  onChanged: (val) {
                    libProvider.search(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 书籍网格展示
          Expanded(
            child: libProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : libProvider.books.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty ? '当前书库空空如也' : '未找到相关书籍',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: 0.6,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: libProvider.books.length,
                        itemBuilder: (context, index) {
                          final book = libProvider.books[index];
                          return _buildBookCard(book, storageService);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // 每一本书的卡片
  Widget _buildBookCard(Book book, StorageService storage) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseUrl = storage.getServerUrl() ?? '';
    final token = storage.getToken() ?? '';
    final userAgent = storage.getCustomUA();

    return InkWell(
      onTap: () {
        // 打开书籍详情页面
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookDetailView(book: book),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceVariant.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图 (使用 CachedNetworkImage 并在硬盘上持久缓存，同时伪装 User-Agent)
            Expanded(
              child: Container(
                width: double.infinity,
                color: colorScheme.surfaceVariant,
                child: CachedNetworkImage(
                  imageUrl: book.getCoverUrl(baseUrl),
                  httpHeaders: {
                    'User-Agent': userAgent,
                    'Authorization': 'Bearer $token',
                  },
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Center(
                    child: Icon(
                      Icons.book,
                      size: 48,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            // 元数据信息
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建设置视图
  Widget _buildSettingsView() {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final uaController = TextEditingController(text: auth.customUA);

    return Scaffold(
      appBar: AppBar(
        title: const Text('客户端设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '网络伪装与 User-Agent',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '此项设置会自动附加于所有的 API 请求与音频/图片流传输层。建议使用默认值，如果您有特定的有声书服，可以根据服主提示输入对应的伪装标识符。',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: uaController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '当前生效的 User-Agent',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          await auth.updateCustomUA(uaController.text.trim());
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('User-Agent 更新成功！')),
                            );
                          }
                        },
                        child: const Text('保存修改'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          uaController.text = AppConstants.defaultUserAgent;
                        },
                        child: const Text('重置为默认 (官方 Android)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '连接状态',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('服务器地址'),
                    subtitle: Text(auth.serverUrl ?? '未配置'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  ListTile(
                    title: const Text('当前登录账户'),
                    subtitle: Text(auth.username ?? '未登录'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  ListTile(
                    title: const Text('客户端内核'),
                    subtitle: const Text('Flutter M3 + mpv Engine (media_kit)'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定要退出当前服务器登录吗？您的本地连接信息将会被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthProvider>().logout();
            },
            child: const Text('确定登出', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

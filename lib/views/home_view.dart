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
import 'debug_logs_dialog.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _navIndex = 0; // 0: 书架, 1: 设置
  final _searchController = TextEditingController();

  String? _selectedArtistId;
  String? _selectedArtistName;
  List<Book> _artistAlbums = [];
  bool _isLoadingArtistAlbums = false;

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
    final playbackProvider = context.watch<PlaybackProvider>();
    final auth = context.read<AuthProvider>();
    final isSubsonic = auth.isSubsonicMode;

    // 动态生成导航目的地
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.library_books),
        selectedIcon: Icon(Icons.library_books_rounded),
        label: Text('书架'),
      ),
      if (isSubsonic) ...[
        const NavigationRailDestination(
          icon: Icon(Icons.people),
          selectedIcon: Icon(Icons.people_alt),
          label: Text('歌手'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.playlist_play),
          selectedIcon: Icon(Icons.playlist_play_rounded),
          label: Text('歌单'),
        ),
      ],
      const NavigationRailDestination(
        icon: Icon(Icons.settings),
        selectedIcon: Icon(Icons.settings_applications),
        label: Text('设置'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.logout, color: Colors.redAccent),
        label: Text('登出', style: TextStyle(color: Colors.redAccent)),
      ),
    ];

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
                    if (index == destinations.length - 1) {
                      // 退出登录
                      _showLogoutDialog();
                    } else {
                      setState(() {
                        _navIndex = index;
                        // 切换 Tab 时自动重置歌手二级页面
                        _selectedArtistId = null;
                        _selectedArtistName = null;
                        _artistAlbums = [];
                      });

                      // 切换时静默更新下分类数据
                      if (isSubsonic) {
                        if (index == 1) {
                          context.read<LibraryProvider>().fetchArtists();
                        } else if (index == 2) {
                          context.read<LibraryProvider>().fetchPlaylists();
                        }
                      }
                    }
                  },
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Icon(Icons.headphones, size: 36),
                  ),
                  destinations: destinations,
                ),
                const VerticalDivider(thickness: 1, width: 1),

                // 2. 右侧主体页面
                Expanded(
                  child: _buildBody(isSubsonic),
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

          // 扁平彩色分类卡片入口栏
          _buildCategoryTiles(libProvider),

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
    final proxyController = TextEditingController(text: auth.httpProxy ?? '127.0.0.1:7890');

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
                    '网络代理设置',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '如果您使用的有声书服务器或 RSS 源需要科学上网，请在下方设置您的本地 HTTP 代理地址。若不输入协议头（如 http://）会自动默认补全。',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: proxyController,
                    decoration: const InputDecoration(
                      labelText: 'HTTP 代理服务器地址',
                      hintText: '例如: 127.0.0.1:7890 (留空表示直连)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          await auth.updateHttpProxy(proxyController.text.trim());
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('网络代理配置更新成功！')),
                            );
                          }
                        },
                        child: const Text('保存代理设置'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () async {
                          proxyController.clear();
                          await auth.updateHttpProxy('');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已清空代理并切换为直连模式')),
                            );
                          }
                        },
                        child: const Text('清空并直连'),
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
                  const Divider(),
                  ListTile(
                    title: const Text('调试日志'),
                    subtitle: const Text('查看应用运行诊断与网络响应日志'),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => const DebugLogsDialog(),
                      );
                    },
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

  // 根据当前导航状态路由对应的主页面
  Widget _buildBody(bool isSubsonic) {
    if (isSubsonic) {
      if (_navIndex == 0) return _buildLibraryView();
      if (_navIndex == 1) return _buildArtistsView();
      if (_navIndex == 2) return _buildPlaylistsView();
      return _buildSettingsView();
    } else {
      if (_navIndex == 0) return _buildLibraryView();
      return _buildSettingsView();
    }
  }

  // 构建歌手分类列表和二级专辑列表页面
  Widget _buildArtistsView() {
    final libProvider = context.watch<LibraryProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final storageService = context.read<StorageService>();

    // 二级页面：某歌手的专辑列表
    if (_selectedArtistId != null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedArtistId = null;
                      _selectedArtistName = null;
                      _artistAlbums = [];
                    });
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  '$_selectedArtistName 的有声专辑',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoadingArtistAlbums
                  ? const Center(child: CircularProgressIndicator())
                  : _artistAlbums.isEmpty
                      ? const Center(child: Text('该歌手暂无专辑数据'))
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            childAspectRatio: 0.6,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                          ),
                          itemCount: _artistAlbums.length,
                          itemBuilder: (context, index) {
                            final book = _artistAlbums[index];
                            return _buildBookCard(book, storageService);
                          },
                        ),
            ),
          ],
        ),
      );
    }

    // 一级页面：歌手列表网格
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '歌手分类',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: libProvider.isLoadingArtists
                ? const Center(child: CircularProgressIndicator())
                : libProvider.artists.isEmpty
                    ? const Center(child: Text('暂无歌手分类数据'))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          childAspectRatio: 1.1,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: libProvider.artists.length,
                        itemBuilder: (context, index) {
                          final artist = libProvider.artists[index];
                          final id = artist['id'] as String;
                          final name = artist['name'] as String;
                          final count = artist['albumCount'] as int;

                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withOpacity(0.3),
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                setState(() {
                                  _selectedArtistId = id;
                                  _selectedArtistName = name;
                                  _isLoadingArtistAlbums = true;
                                });
                                final albums = await libProvider.fetchArtistAlbums(id);
                                setState(() {
                                  _artistAlbums = albums;
                                  _isLoadingArtistAlbums = false;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: colorScheme.primary.withOpacity(0.1),
                                      child: Text(
                                        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$count 个有声书',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // 构建歌单列表页并直接映射到虚拟有声书播单
  Widget _buildPlaylistsView() {
    final libProvider = context.watch<LibraryProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的歌单',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: libProvider.isLoadingPlaylists
                ? const Center(child: CircularProgressIndicator())
                : libProvider.playlists.isEmpty
                    ? const Center(child: Text('暂无歌单数据'))
                    : ListView.builder(
                        itemCount: libProvider.playlists.length,
                        itemBuilder: (context, index) {
                          final p = libProvider.playlists[index];
                          final id = p['id'] as String;
                          final name = p['name'] as String;
                          final count = p['songCount'] as int;
                          final duration = p['duration'] as double;

                          final hrs = (duration / 3600).floor();
                          final mins = ((duration % 3600) / 60).floor();
                          final durationStr = hrs > 0 ? '$hrs 小时 $mins 分钟' : '$mins 分钟';

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withOpacity(0.3),
                              ),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.secondary.withOpacity(0.1),
                                child: Icon(Icons.queue_music, color: colorScheme.secondary),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text('共 $count 首歌曲 • 总播放时长: $durationStr'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (ctx) => const Center(child: CircularProgressIndicator()),
                                );
                                
                                final virtualBook = await libProvider.fetchPlaylistTracksAsBook(id, name);
                                if (mounted) {
                                  Navigator.pop(context); // 关闭加载弹窗
                                  if (virtualBook != null) {
                                    // 完美无缝跳转到书籍详情页进行章节化播放！
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (ctx) => BookDetailView(book: virtualBook),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('歌单数据加载失败')),
                                    );
                                  }
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // 构建扁平多色卡片分类横幅 (完全对照手机端彩色分类磁贴排版)
  Widget _buildCategoryTiles(LibraryProvider libProvider) {
    final isSubsonic = context.read<AuthProvider>().isSubsonicMode;
    if (!isSubsonic) return const SizedBox.shrink();

    // 智能估算歌曲总数 (累加所有专辑里面的歌曲章节音轨数)
    final songCount = libProvider.books.fold<int>(0, (sum, book) => sum + (book.chapters.isNotEmpty ? book.chapters.length : 1));
    final albumCount = libProvider.books.length;
    final artistCount = libProvider.artists.length;
    final playlistCount = libProvider.playlists.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          // 1. 歌曲 (绿色，手机端 #2E7D32)
          Expanded(
            child: _buildCategoryCard(
              title: '歌曲',
              count: songCount.toString(),
              icon: Icons.music_note_rounded,
              color: Colors.green,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已自动拉取加载全部歌曲，您可直接在上方进行搜索播放！')),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          // 2. 专辑 (橙色，手机端 #EF6C00)
          Expanded(
            child: _buildCategoryCard(
              title: '专辑',
              count: albumCount.toString(),
              icon: Icons.album_rounded,
              color: Colors.orange,
              onTap: () {
                setState(() {
                  _navIndex = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 16),
          // 3. 歌手 (蓝色，手机端 #1565C0)
          Expanded(
            child: _buildCategoryCard(
              title: '歌手',
              count: artistCount.toString(),
              icon: Icons.people_rounded,
              color: Colors.blue,
              onTap: () {
                setState(() {
                  _navIndex = 1;
                });
                context.read<LibraryProvider>().fetchArtists();
              },
            ),
          ),
          const SizedBox(width: 16),
          // 4. 歌单 (红色，手机端 #C2185B)
          Expanded(
            child: _buildCategoryCard(
              title: '歌单',
              count: playlistCount.toString(),
              icon: Icons.playlist_play_rounded,
              color: Colors.pink,
              onTap: () {
                setState(() {
                  _navIndex = 2;
                });
                context.read<LibraryProvider>().fetchPlaylists();
              },
            ),
          ),
        ],
      ),
    );
  }

  // 快捷入口卡片细节渲染
  Widget _buildCategoryCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.25), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.15),
                radius: 22,
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

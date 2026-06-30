import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import 'debug_logs_dialog.dart';

class ServerSelectorView extends StatefulWidget {
  const ServerSelectorView({super.key});

  @override
  State<ServerSelectorView> createState() => _ServerSelectorViewState();
}

class _ServerSelectorViewState extends State<ServerSelectorView> {
  int _filterTab = 0; // 0: 全部, 1: ABS, 2: RSS, 3: Navidrome
  bool _obscureUrls = true;
  List<Map<String, dynamic>> _profiles = [];
  String? _connectingProfileId;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  void _loadProfiles() {
    final storage = context.read<StorageService>();
    setState(() {
      _profiles = storage.getServerProfiles();
    });
    // 如果没有任何已保存的 Profile，自动跳转到登录页
    if (_profiles.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AuthProvider>().switchToLogin();
      });
    }
  }

  List<Map<String, dynamic>> get _filteredProfiles {
    if (_filterTab == 0) return _profiles;
    final typeIndex = _filterTab - 1; // 0: ABS, 1: RSS, 2: Navidrome
    return _profiles.where((p) => (p['type'] as int? ?? 0) == typeIndex).toList();
  }

  // 获取协议的图标和颜色
  _ProfileStyle _getProfileStyle(int type) {
    switch (type) {
      case 1:
        return _ProfileStyle(Icons.rss_feed, Colors.green, 'RSS');
      case 2:
        return _ProfileStyle(Icons.album, Colors.blue, 'Navidrome');
      default:
        return _ProfileStyle(Icons.headphones, Colors.amber, 'ABS');
    }
  }

  // 格式化敏感地址输出（打码）
  String _formatUrlDisplay(String url) {
    if (!_obscureUrls) return url;
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (host.isEmpty) return '***';
      if (host.length > 4) {
        final start = host.substring(0, 2);
        final end = host.substring(host.length - 2);
        final obscuredHost = '$start***$end';
        return url.replaceFirst(host, obscuredHost);
      }
      return '***';
    } catch (_) {
      if (url.length > 10) {
        return '${url.substring(0, 6)}***${url.substring(url.length - 4)}';
      }
      return '***';
    }
  }

  // 连接到选中的 Profile
  Future<void> _connectToProfile(Map<String, dynamic> profile) async {
    final profileId = profile['id'] as String? ?? '';
    setState(() {
      _connectingProfileId = profileId;
    });

    final auth = context.read<AuthProvider>();
    final success = await auth.connectToProfile(profile);

    if (mounted) {
      setState(() {
        _connectingProfileId = null;
      });
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.errorMessage ?? '连接失败'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // Profile 操作菜单
  Future<void> _handleProfileAction(String action, Map<String, dynamic> profile, int index) async {
    final storage = context.read<StorageService>();
    if (action == 'edit_config') {
      context.read<AuthProvider>().switchToLogin(profile: profile);
    } else if (action == 'rename') {
      final controller = TextEditingController(text: profile['name']);
      final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重命名服务器'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: '备注名称'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (newName != null && newName.isNotEmpty) {
        setState(() {
          _profiles[index]['name'] = newName;
        });
        await storage.saveServerProfiles(_profiles);
      }
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除服务器'),
          content: Text('确定删除 "${profile['name']}" 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        setState(() {
          _profiles.removeAt(index);
        });
        await storage.saveServerProfiles(_profiles);
        // 如果删光了所有 Profile，自动跳转到登录页
        if (_profiles.isEmpty) {
          if (mounted) context.read<AuthProvider>().switchToLogin();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeProfileId = context.read<StorageService>().getActiveProfileId();
    final filtered = _filteredProfiles;

    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部标题栏
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.dns_rounded,
                            size: 28,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '服务器',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                        ),
                        const Spacer(),
                        // 隐私模式切换
                        IconButton(
                          icon: Icon(
                            _obscureUrls ? Icons.visibility_off : Icons.visibility,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          tooltip: _obscureUrls ? '显示完整地址' : '隐藏敏感地址',
                          onPressed: () {
                            setState(() {
                              _obscureUrls = !_obscureUrls;
                            });
                          },
                        ),
                        const SizedBox(width: 4),
                        // 添加新服务器
                        FilledButton.icon(
                          onPressed: () {
                            context.read<AuthProvider>().switchToLogin();
                          },
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('添加服务器'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Tab 过滤栏
                    Row(
                      children: [
                        _buildFilterChip('全部', 0, null),
                        const SizedBox(width: 8),
                        _buildFilterChip('ABS', 1, Colors.amber),
                        const SizedBox(width: 8),
                        _buildFilterChip('RSS', 2, Colors.green),
                        const SizedBox(width: 8),
                        _buildFilterChip('Navidrome', 3, Colors.blue),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 服务器卡片网格
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cloud_off,
                                      size: 64,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                                  const SizedBox(height: 16),
                                  Text(
                                    _filterTab == 0 ? '暂无已保存的服务器' : '该分类下暂无服务器',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : GridView.builder(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 340,
                                childAspectRatio: 2.0,
                                crossAxisSpacing: 20,
                                mainAxisSpacing: 20,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final profile = filtered[index];
                                // 在完整列表中找到真实索引
                                final realIndex = _profiles.indexOf(profile);
                                return _buildServerCard(
                                  profile,
                                  realIndex,
                                  activeProfileId,
                                  colorScheme,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 右下角调试日志入口
          Positioned(
            bottom: 20,
            right: 20,
            child: TextButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => const DebugLogsDialog(),
                );
              },
              icon: const Icon(Icons.terminal, size: 16),
              label: const Text('调试日志', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int index, Color? dotColor) {
    final isSelected = _filterTab == index;
    final colorScheme = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _filterTab = index;
          });
        }
      },
      selectedColor: colorScheme.primaryContainer,
    );
  }

  Widget _buildServerCard(
    Map<String, dynamic> profile,
    int realIndex,
    String? activeProfileId,
    ColorScheme colorScheme,
  ) {
    final type = profile['type'] as int? ?? 0;
    final style = _getProfileStyle(type);
    final profileId = profile['id'] as String? ?? '';
    final isActive = profileId == activeProfileId;
    final isConnecting = _connectingProfileId == profileId;

    return Card(
      elevation: isActive ? 4 : 0,
      color: isActive
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? colorScheme.primary.withValues(alpha: 0.6) : colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: isActive ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: isConnecting ? null : () => _connectToProfile(profile),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 协议图标
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: isConnecting
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: style.color,
                        ),
                      )
                    : Icon(style.icon, color: style.color, size: 28),
              ),
              const SizedBox(width: 14),
              // 服务器信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      profile['name'] ?? '未命名',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatUrlDisplay(profile['url'] ?? ''),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: style.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            style.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: style.color,
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '上次连接',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.tealAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 三点菜单
              PopupMenuButton<String>(
                onSelected: (action) => _handleProfileAction(action, profile, realIndex),
                icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit_config',
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('编辑配置'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('快速重命名'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.redAccent, size: 18),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 辅助类：Profile 卡片样式
class _ProfileStyle {
  final IconData icon;
  final Color color;
  final String label;
  const _ProfileStyle(this.icon, this.color, this.label);
}

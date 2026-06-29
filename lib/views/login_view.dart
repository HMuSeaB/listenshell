import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../constants/app_constants.dart';
import '../services/storage_service.dart';
import 'debug_logs_dialog.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _uaController = TextEditingController();
  final _proxyController = TextEditingController();

  int _loginTab = 0; // 0: ABS, 1: RSS, 2: Navidrome
  bool _useHttps = true;
  bool _showPassword = false;
  bool _showAdvanced = false;
  String _selectedUAPreset = 'Android'; // 'Android', 'DSOne', 'Custom'

  List<Map<String, dynamic>> _profiles = [];
  bool _obscureUrls = true; // 是否对敏感地址进行打码展示

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    // 回填保存的数据
    final savedUrl = auth.serverUrl ?? '';
    final savedUsername = auth.username ?? '';

    if (auth.isRssMode) {
      _loginTab = 1;
      _hostController.text = savedUrl;
    } else if (auth.isSubsonicMode) {
      _loginTab = 2;
      _useHttps = savedUrl.startsWith('https://');
      var cleanHost = savedUrl.replaceFirst('https://', '').replaceFirst('http://', '');
      if (cleanHost.contains(':')) {
        final parts = cleanHost.split(':');
        _hostController.text = parts[0];
        _portController.text = parts[1];
      } else {
        _hostController.text = cleanHost;
      }
      _usernameController.text = savedUsername;
    } else {
      _loginTab = 0;
      if (savedUrl.isNotEmpty) {
        _useHttps = savedUrl.startsWith('https://');
        var cleanHost = savedUrl.replaceFirst('https://', '').replaceFirst('http://', '');
        if (cleanHost.contains(':')) {
          final parts = cleanHost.split(':');
          _hostController.text = parts[0];
          _portController.text = parts[1];
        } else {
          _hostController.text = cleanHost;
        }
      }
      _usernameController.text = savedUsername;
    }
    
    // 初始化 UA 输入
    final currentUA = auth.customUA;
    if (currentUA == AppConstants.defaultUserAgent) {
      _selectedUAPreset = 'Android';
      _uaController.text = AppConstants.defaultUserAgent;
    } else if (currentUA == AppConstants.dsOneUserAgent) {
      _selectedUAPreset = 'DSOne';
      _uaController.text = AppConstants.dsOneUserAgent;
    } else {
      _selectedUAPreset = 'Custom';
      _uaController.text = currentUA;
    }

    // 初始化代理输入，若本地没有保存过，默认预填 127.0.0.1:7890 以便用户一键连接
    _proxyController.text = auth.httpProxy ?? '127.0.0.1:7890';

    // 从存储服务加载历史服务器配置
    final storage = context.read<StorageService>();
    _profiles = storage.getServerProfiles();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _uaController.dispose();
    _proxyController.dispose();
    super.dispose();
  }

  // 拼接得到完整地址
  String _buildFullUrl() {
    var host = _hostController.text.trim();
    if (_loginTab == 1) {
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        return 'http://$host';
      }
      return host;
    }

    // 移除用户不小心写的协议前缀
    host = host.replaceFirst('https://', '').replaceFirst('http://', '');
    
    final port = _portController.text.trim();
    final protocol = _useHttps ? 'https://' : 'http://';
    
    if (port.isNotEmpty) {
      return '$protocol$host:$port';
    }
    return '$protocol$host';
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    
    // 保存 UA
    await auth.updateCustomUA(_uaController.text.trim());
    // 保存并应用全局代理
    await auth.updateHttpProxy(_proxyController.text.trim());

    final fullUrl = _buildFullUrl();
    
    bool success;
    if (_loginTab == 1) {
      success = await auth.loginRss(fullUrl);
    } else if (_loginTab == 2) {
      success = await auth.loginSubsonic(
        fullUrl,
        _usernameController.text.trim(),
        _passwordController.text,
      );
    } else {
      success = await auth.login(
        fullUrl,
        _usernameController.text.trim(),
        _passwordController.text,
      );
    }

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_loginTab == 1 ? '订阅源连接成功！' : '登录成功！')),
      );
      // 登录验证成功后，保存/更新服务器历史配置
      await _promptProfileNameAndSave();
    }
  }

  // 静默命名并保存 Profile (模仿手机端 DSOne 自动生成名字)
  Future<void> _promptProfileNameAndSave() async {
    final fullUrl = _buildFullUrl();
    var defaultName = '';
    try {
      final uri = Uri.parse(fullUrl);
      defaultName = uri.host;
      if (defaultName.isEmpty) defaultName = fullUrl;
    } catch (_) {
      defaultName = fullUrl;
    }

    String prefix = 'ABS';
    if (_loginTab == 1) {
      prefix = 'RSS';
    } else if (_loginTab == 2) {
      prefix = 'Navidrome';
    }
    
    final finalName = '$prefix ($defaultName)';
    await _saveCurrentProfile(finalName);
  }

  // 执行具体写入 Profile 历史
  Future<void> _saveCurrentProfile(String name) async {
    final storage = context.read<StorageService>();
    final fullUrl = _buildFullUrl();
    final username = _usernameController.text.trim();
    final customUA = _uaController.text.trim();

    final newProfile = {
      'id': 'profile_${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'type': _loginTab, // 0: ABS, 1: RSS, 2: Navidrome
      'url': fullUrl,
      'username': _loginTab == 1 ? '' : username,
      'password': _loginTab == 1 ? '' : _passwordController.text,
      'customUAPreset': _selectedUAPreset,
      'customUA': customUA,
      'httpProxy': _proxyController.text.trim(),
    };

    final existingIdx = _profiles.indexWhere((p) =>
        p['url'] == fullUrl &&
        p['username'] == newProfile['username'] &&
        p['type'] == newProfile['type']);

    if (existingIdx != -1) {
      newProfile['name'] = _profiles[existingIdx]['name'] ?? name;
      newProfile['id'] = _profiles[existingIdx]['id'];
      _profiles[existingIdx] = newProfile;
    } else {
      _profiles.add(newProfile);
    }

    await storage.saveServerProfiles(_profiles);
    setState(() {});
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

  // 服务器记录卡片右侧 ⋮ 的操作
  Future<void> _handleProfileMenu(String action, Map<String, dynamic> p, int index) async {
    if (action == 'connect') {
      setState(() {
        _loginTab = p['type'] as int? ?? 0;
        final url = p['url'] as String? ?? '';
        _useHttps = url.startsWith('https://');

        var clean = url.replaceFirst('https://', '').replaceFirst('http://', '');
        if (clean.contains(':') && _loginTab != 1) {
          final parts = clean.split(':');
          _hostController.text = parts[0];
          _portController.text = parts[1];
        } else {
          _hostController.text = clean;
          _portController.text = '';
        }

        _usernameController.text = p['username'] as String? ?? '';
        _passwordController.text = p['password'] as String? ?? '';
        _selectedUAPreset = p['customUAPreset'] as String? ?? 'Android';
        _uaController.text = p['customUA'] as String? ?? AppConstants.defaultUserAgent;
        _proxyController.text = p['httpProxy'] as String? ?? '127.0.0.1:7890';
      });

      _handleLogin();
    } else if (action == 'rename') {
      final controller = TextEditingController(text: p['name']);
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
        final storage = context.read<StorageService>();
        await storage.saveServerProfiles(_profiles);
      }
    } else if (action == 'delete') {
      setState(() {
        _profiles.removeAt(index);
      });
      final storage = context.read<StorageService>();
      await storage.saveServerProfiles(_profiles);
    }
  }

  // 构建左侧的服务器历史列表面板
  Widget _buildProfileManager(ColorScheme colorScheme) {
    return Container(
      width: 360,
      height: 600,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '服务器',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: colorScheme.onSurface,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(_obscureUrls ? Icons.visibility_off : Icons.visibility),
                tooltip: _obscureUrls ? '显示完整地址' : '隐藏敏感地址',
                onPressed: () {
                  setState(() {
                    _obscureUrls = !_obscureUrls;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '新建连接',
                onPressed: () {
                  setState(() {
                    _hostController.clear();
                    _portController.clear();
                    _usernameController.clear();
                    _passwordController.clear();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _profiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off, size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          '暂无保存的服务器',
                          style: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _profiles.length,
                    itemBuilder: (context, index) {
                      final p = _profiles[index];
                      final type = p['type'] as int? ?? 0;

                      IconData iconData;
                      Color iconColor;
                      String typeName;
                      if (type == 1) {
                        iconData = Icons.rss_feed;
                        iconColor = Colors.green;
                        typeName = 'RSS';
                      } else if (type == 2) {
                        iconData = Icons.album;
                        iconColor = Colors.blue;
                        typeName = 'Navidrome';
                      } else {
                        iconData = Icons.headphones;
                        iconColor = Colors.amber;
                        typeName = 'ABS';
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withOpacity(0.3),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.only(left: 16, right: 8, top: 4, bottom: 4),
                          leading: CircleAvatar(
                            backgroundColor: iconColor.withOpacity(0.2),
                            child: Icon(iconData, color: iconColor),
                          ),
                          title: Text(
                            p['name'] ?? '未命名',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                _formatUrlDisplay(p['url'] ?? ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '协议: $typeName',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) => _handleProfileMenu(action, p, index),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'connect',
                                child: Row(
                                  children: [
                                    Icon(Icons.login, size: 18),
                                    SizedBox(width: 8),
                                    Text('一键连接'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 18),
                                    SizedBox(width: 8),
                                    Text('重命名'),
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // 右上角调试日志入口
          Positioned(
            top: 20,
            right: 20,
            child: TextButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => const DebugLogsDialog(),
                );
              },
              icon: const Icon(Icons.terminal),
              label: const Text('调试日志'),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧：服务器历史记录管理
                    _buildProfileManager(colorScheme),
                    const SizedBox(width: 24),
                    // 右侧：原登录界面
                    Container(
                      width: 480,
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 头部 Logo 与应用名
                            Center(
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.headphones,
                                      size: 48,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    AppConstants.appName,
                                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '高性能有声书电脑客户端',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 登录模式切换 Tab ChoiceChips
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ChoiceChip(
                                  label: const Text('标准 (ABS)'),
                                  selected: _loginTab == 0,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _loginTab = 0;
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('RSS 订阅'),
                                  selected: _loginTab == 1,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _loginTab = 1;
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Navidrome'),
                                  selected: _loginTab == 2,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _loginTab = 2;
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // 服务器配置
                            Text(
                              _loginTab == 1 ? '订阅源配置' : '服务器连接',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _hostController,
                                    decoration: InputDecoration(
                                      labelText: _loginTab == 1 ? 'RSS 订阅链接' : '主机地址 (Host)',
                                      hintText: _loginTab == 1 
                                          ? '例如 http://.../feed/f8face...'
                                          : '如: 192.168.1.100 或 nd.com',
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(Icons.dns),
                                    ),
                                    validator: (value) =>
                                        (value == null || value.trim().isEmpty) ? '请输入地址' : null,
                                  ),
                                ),
                                if (_loginTab != 1) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: TextFormField(
                                      controller: _portController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: '端口 (Port)',
                                        hintText: '可选',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (_loginTab != 1) ...[
                              // HTTPS 切换
                              SwitchListTile(
                                title: const Text('启用安全连接 (HTTPS)'),
                                subtitle: const Text('优先推荐启用，若内网部署或无 SSL 证书可关闭'),
                                value: _useHttps,
                                onChanged: (val) {
                                  setState(() {
                                    _useHttps = val;
                                  });
                                },
                                contentPadding: EdgeInsets.zero,
                              ),
                              const Divider(height: 24),
                            ],

                            if (_loginTab != 1) ...[
                              // 用户凭据
                              Text(
                                '登录凭据',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _usernameController,
                                decoration: const InputDecoration(
                                  labelText: '用户名',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person),
                                ),
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty) ? '请输入用户名' : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: !_showPassword,
                                decoration: InputDecoration(
                                  labelText: '密码',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
                                    onPressed: () {
                                      setState(() {
                                        _showPassword = !_showPassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) =>
                                    (value == null || value.isEmpty) ? '请输入密码' : null,
                              ),
                                const SizedBox(height: 16),
                            ],

                            // 高级设置 (User-Agent 伪装)
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _showAdvanced = !_showAdvanced;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      _showAdvanced ? Icons.expand_less : Icons.expand_more,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '高级设置 (User-Agent 伪装)',
                                      style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_showAdvanced) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('预设：'),
                                  ChoiceChip(
                                    label: const Text('官方 Android'),
                                    selected: _selectedUAPreset == 'Android',
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _selectedUAPreset = 'Android';
                                          _uaController.text = AppConstants.defaultUserAgent;
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('DSOne 客户端'),
                                    selected: _selectedUAPreset == 'DSOne',
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _selectedUAPreset = 'DSOne';
                                          _uaController.text = AppConstants.dsOneUserAgent;
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('自定义'),
                                    selected: _selectedUAPreset == 'Custom',
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _selectedUAPreset = 'Custom';
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _uaController,
                                enabled: _selectedUAPreset == 'Custom',
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'User-Agent 请求头',
                                  border: OutlineInputBorder(),
                                  helperText: '某些私有服限制了网页播放，必须伪装成手机 App 请求头以规避风控。',
                                ),
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty) ? 'User-Agent 不能为空' : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _proxyController,
                                decoration: const InputDecoration(
                                  labelText: 'HTTP 代理服务器',
                                  hintText: '例如: 127.0.0.1:7890 (留空表示直连)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.network_ping),
                                  helperText: '若您的服务器或 RSS 源需要科学上网，请输入代理。协议头会自动补充。',
                                ),
                              ),
                            ],

                            if (auth.errorMessage != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                auth.errorMessage!,
                                style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w500),
                              ),
                            ],

                            const SizedBox(height: 32),

                            // 登录按钮
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: auth.isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: auth.isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : Text(
                                        _loginTab == 1 ? '解析并播放' : '连接并登录',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

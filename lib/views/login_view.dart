import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../constants/app_constants.dart';
import '../services/storage_service.dart';
import 'debug_logs_dialog.dart';

class LoginView extends StatefulWidget {
  final Map<String, dynamic>? profileToEdit;
  const LoginView({super.key, this.profileToEdit});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
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

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();

    final toEdit = widget.profileToEdit;
    if (toEdit != null) {
      // 1. 进入编辑配置模式
      _loginTab = toEdit['type'] as int? ?? 0;
      _nameController.text = toEdit['name'] as String? ?? '';
      
      final url = toEdit['url'] as String? ?? '';
      if (_loginTab == 1) {
        // RSS
        _hostController.text = url;
      } else {
        // 解析主机与端口
        try {
          final uri = Uri.parse(url);
          _useHttps = uri.scheme == 'https';
          _hostController.text = uri.host;
          if (uri.hasPort) {
            _portController.text = uri.port.toString();
          } else {
            _portController.text = '';
          }
        } catch (_) {
          _hostController.text = url;
        }
      }

      _usernameController.text = toEdit['username'] as String? ?? '';
      _passwordController.text = toEdit['password'] as String? ?? '';
      
      final ua = toEdit['customUA'] as String? ?? '';
      _selectedUAPreset = toEdit['customUAPreset'] as String? ?? 'Android';
      _uaController.text = ua.isNotEmpty ? ua : AppConstants.defaultUserAgent;
      
      _proxyController.text = toEdit['httpProxy'] as String? ?? '';
      _showAdvanced = true; // 自动展开显示高级代理设置
    } else {
      // 2. 普通添加模式
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

      // 初始化代理输入
      _proxyController.text = auth.httpProxy ?? '127.0.0.1:7890';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
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

  // 测试并连接登录
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
      // 登录成功后保存/更新 Profile
      await _saveProfileSilently();
    }
  }

  // 仅保存修改并不连接 (仅限编辑模式)
  Future<void> _saveOnly() async {
    if (!_formKey.currentState!.validate()) return;
    
    await _saveProfileSilently();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置修改已保存！')),
      );
      context.read<AuthProvider>().switchToServerSelector();
    }
  }

  // 保存或更新 Profile 数据
  Future<void> _saveProfileSilently() async {
    final fullUrl = _buildFullUrl();
    
    // 如果用户输入了名称，使用用户输入的，否则自动根据 host 生成
    var finalName = _nameController.text.trim();
    if (finalName.isEmpty) {
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
      finalName = '$prefix ($defaultName)';
    }

    final storage = context.read<StorageService>();
    final profiles = storage.getServerProfiles();
    final username = _usernameController.text.trim();

    // 如果是编辑模式，保持原有的 ID
    final String profileId = widget.profileToEdit != null
        ? (widget.profileToEdit!['id'] as String? ?? 'profile_${DateTime.now().millisecondsSinceEpoch}')
        : 'profile_${DateTime.now().millisecondsSinceEpoch}';

    final newProfile = {
      'id': profileId,
      'name': finalName,
      'type': _loginTab, // 0: ABS, 1: RSS, 2: Navidrome
      'url': fullUrl,
      'username': _loginTab == 1 ? '' : username,
      'password': _loginTab == 1 ? '' : _passwordController.text,
      'customUAPreset': _selectedUAPreset,
      'customUA': _uaController.text.trim(),
      'httpProxy': _proxyController.text.trim(),
    };

    final existingIdx = profiles.indexWhere((p) => p['id'] == profileId);

    if (existingIdx != -1) {
      profiles[existingIdx] = newProfile;
    } else {
      // 容错：如果通过 ID 未匹配到，则按 url 查重
      final urlIdx = profiles.indexWhere((p) =>
          p['url'] == fullUrl &&
          p['username'] == newProfile['username'] &&
          p['type'] == newProfile['type']);
      if (urlIdx != -1) {
        newProfile['id'] = profiles[urlIdx]['id'];
        profiles[urlIdx] = newProfile;
      } else {
        profiles.add(newProfile);
      }
    }

    await storage.saveServerProfiles(profiles);
    await storage.setActiveProfileId(newProfile['id'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final hasProfiles = context.read<StorageService>().getServerProfiles().isNotEmpty;
    final isEditMode = widget.profileToEdit != null;

    return Scaffold(
      body: Stack(
        children: [
          // 左上角返回按钮
          if (hasProfiles)
            Positioned(
              top: 20,
              left: 20,
              child: TextButton.icon(
                onPressed: () {
                  context.read<AuthProvider>().switchToServerSelector();
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回服务器列表'),
              ),
            ),
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
                child: Container(
                  width: 500,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
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
                        // 头部 Logo 与自适应标题
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
                                  isEditMode ? Icons.edit_note : Icons.add_circle_outline,
                                  size: 48,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                isEditMode ? '编辑服务器配置' : '添加服务器',
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isEditMode ? '修改此音频服务器的连接与代理配置' : '配置一个新的音频服务器连接',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 登录模式切换 Tab ChoiceChips (编辑状态下锁定协议类型以防数据错乱)
                        Center(
                          child: IgnorePointer(
                            ignoring: isEditMode, // 编辑时锁定协议类型，不允许更改类型以避免类型和参数错乱
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ChoiceChip(
                                  label: const Text('标准 (ABS)'),
                                  selected: _loginTab == 0,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() { _loginTab = 0; });
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('RSS 订阅'),
                                  selected: _loginTab == 1,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() { _loginTab = 1; });
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Navidrome'),
                                  selected: _loginTab == 2,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() { _loginTab = 2; });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 字段一：服务器名称 (备注栏，极为关键，防止乱自动生成名字)
                        Text(
                          '基本配置',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: '服务器名称 (备注)',
                            hintText: '如: Navidrome私有音乐库 (留空则根据链接自动命名)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.label_outline),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 服务器地址配置
                        Text(
                          _loginTab == 1 ? '订阅源配置' : '网络连接',
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
                              setState(() { _useHttps = val; });
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
                                  setState(() { _showPassword = !_showPassword; });
                                },
                              ),
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty) ? '请输入密码' : null,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 高级设置 (User-Agent 伪装与代理设置)
                        InkWell(
                          onTap: () {
                            setState(() { _showAdvanced = !_showAdvanced; });
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
                                  '高级设置 (User-Agent 与 独立代理)',
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
                                    setState(() { _selectedUAPreset = 'Custom'; });
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
                              labelText: 'HTTP 代理服务器 (当前连接专有)',
                              hintText: '例如: 127.0.0.1:7890 (留空表示直连)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.network_ping),
                              helperText: '您可以为每个连接配置独立的代理服务器。留空则代表直连。',
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

                        // 保存与登录控制按钮
                        if (isEditMode) ...[
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: OutlinedButton(
                                    onPressed: auth.isLoading ? null : _saveOnly,
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('仅保存修改'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: SizedBox(
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
                                        : const Text(
                                            '测试并连接',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

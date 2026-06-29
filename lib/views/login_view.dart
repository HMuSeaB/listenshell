import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../constants/app_constants.dart';

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

  int _loginTab = 0; // 0: ABS, 1: RSS, 2: Navidrome
  bool _useHttps = true;
  bool _showPassword = false;
  bool _showAdvanced = false;
  String _selectedUAPreset = 'Android'; // 'Android', 'DSOne', 'Custom'

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
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _uaController.dispose();
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Container(
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
        ),
      ),
    );
  }
}

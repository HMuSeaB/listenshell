class ServerConfig {
  final String url;
  final String username;
  final String? token;
  final String? userId;

  ServerConfig({
    required this.url,
    required this.username,
    this.token,
    this.userId,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'username': username,
    'token': token,
    'userId': userId,
  };

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      url: json['url'] as String,
      username: json['username'] as String,
      token: json['token'] as String?,
      userId: json['userId'] as String?,
    );
  }
}

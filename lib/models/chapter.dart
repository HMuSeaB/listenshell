class Chapter {
  final int id; // 章节内部排序 ID (0-based)
  final String title;
  final double start; // 开始时间 (秒)
  final double end;   // 结束时间 (秒)
  final double duration;
  final String? audioUrl; // RSS 订阅直连播放源 URL

  Chapter({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.audioUrl,
  }) : duration = end - start;

  factory Chapter.fromJson(Map<String, dynamic> json, int defaultId) {
    return Chapter(
      id: json['id'] as int? ?? defaultId,
      title: json['title'] as String? ?? '章节 $defaultId',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      audioUrl: json['audioUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start': start,
    'end': end,
    if (audioUrl != null) 'audioUrl': audioUrl,
  };
}

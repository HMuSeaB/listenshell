import 'chapter.dart';

class Book {
  final String id;
  final String title;
  final String author;
  final String narrator;
  final String description;
  final double duration; // 总时长 (秒)
  final List<Chapter> chapters;
  final List<Map<String, dynamic>> tracks;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.narrator,
    required this.description,
    required this.duration,
    required this.chapters,
    required this.tracks,
  });

  // 获取封面完整地址
  String getCoverUrl(String baseUrl) {
    // 拼接成 /api/items/{id}/cover
    final cleanUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$cleanUrl/api/items/$id/cover';
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    final media = json['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    
    // 解析章节
    final chaptersList = <Chapter>[];
    if (media['chapters'] != null) {
      final rawChapters = media['chapters'] as List<dynamic>;
      for (var i = 0; i < rawChapters.length; i++) {
        chaptersList.add(Chapter.fromJson(rawChapters[i] as Map<String, dynamic>, i));
      }
    }

    // 解析音轨
    final tracksList = <Map<String, dynamic>>[];
    if (media['tracks'] != null) {
      final rawTracks = media['tracks'] as List<dynamic>;
      for (final t in rawTracks) {
        if (t is Map<String, dynamic>) {
          tracksList.add(t);
        }
      }
    }

    // 如果章节列表为空，但有多个音轨，我们可以根据音轨合成虚拟章节
    if (chaptersList.isEmpty && tracksList.isNotEmpty) {
      double currentStart = 0.0;
      for (var i = 0; i < tracksList.length; i++) {
        final track = tracksList[i];
        final duration = (track['duration'] as num?)?.toDouble() ?? 0.0;
        final title = track['title'] as String? ?? '音轨 ${i + 1}';
        chaptersList.add(Chapter(
          id: i,
          title: title,
          start: currentStart,
          end: currentStart + duration,
        ));
        currentStart += duration;
      }
    }

    return Book(
      id: json['id'] as String? ?? '',
      title: metadata['title'] as String? ?? json['title'] as String? ?? '未知书名',
      author: metadata['authorName'] as String? ?? '未知作者',
      narrator: metadata['narratorName'] as String? ?? '未知朗读者',
      description: metadata['description'] as String? ?? '暂无简介',
      duration: (media['duration'] as num?)?.toDouble() ?? 0.0,
      chapters: chaptersList,
      tracks: tracksList,
    );
  }
}

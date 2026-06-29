import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/library_provider.dart';
import '../providers/playback_provider.dart';
import '../services/storage_service.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import 'player_view.dart';

class BookDetailView extends StatelessWidget {
  final Book book;

  const BookDetailView({super.key, required this.book});

  // 格式化时长 (秒 -> 时分秒)
  String _formatDuration(double seconds) {
    final int h = (seconds / 3600).floor();
    final int m = ((seconds % 3600) / 60).floor();
    final int s = (seconds % 60).floor();
    
    if (h > 0) {
      return '${h}小时${m}分钟';
    }
    return '${m}分钟${s}秒';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final libProvider = context.read<LibraryProvider>();
    final storage = context.read<StorageService>();
    final baseUrl = storage.getServerUrl() ?? '';
    final token = storage.getToken() ?? '';
    final userAgent = storage.getCustomUA();

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<Book?>(
              // 动态抓取书籍的完整详情，确保章节元数据完整无遗漏
              future: libProvider.fetchBookDetails(book.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final detailedBook = snapshot.data ?? book;
                
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. 左侧大卡片：书籍封面和主要元数据
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 大封面
                              Center(
                                child: Container(
                                  width: 240,
                                  height: 360,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 15,
                                        offset: const Offset(0, 8),
                                      )
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: CachedNetworkImage(
                                      imageUrl: detailedBook.getCoverUrl(baseUrl),
                                      httpHeaders: {
                                        'User-Agent': userAgent,
                                        'Authorization': 'Bearer $token',
                                      },
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        color: colorScheme.surfaceVariant,
                                        child: Icon(Icons.book, size: 80, color: colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              
                              // 书名
                              Text(
                                detailedBook.title,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              
                              // 作者 & 朗读者
                              Text('作者: ${detailedBook.author}', style: const TextStyle(fontSize: 15)),
                              const SizedBox(height: 4),
                              Text('朗读者: ${detailedBook.narrator}', style: const TextStyle(fontSize: 15)),
                              const SizedBox(height: 4),
                              Text('总时长: ${_formatDuration(detailedBook.duration)}', style: TextStyle(color: colorScheme.primary)),
                              const Divider(height: 32),
                              
                              // 简介
                              Text(
                                '书籍简介',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                detailedBook.description,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    
                    const VerticalDivider(width: 1, thickness: 1),

                    // 2. 右侧面板：章节列表与播放按钮
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 顶部播放大按钮
                            Row(
                              children: [
                                Text(
                                  '章节列表 (${detailedBook.chapters.length})',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const Spacer(),
                                
                                // 显式的“继续收听/开始播放”按钮
                                Consumer<PlaybackProvider>(
                                  builder: (context, playProvider, _) {
                                    final isCurrentBook = playProvider.currentBook?.id == detailedBook.id;
                                    return ElevatedButton.icon(
                                      onPressed: playProvider.isLoading
                                          ? null
                                          : () {
                                              if (isCurrentBook) {
                                                playProvider.playOrPause();
                                              } else {
                                                playProvider.playBook(detailedBook);
                                              }
                                            },
                                      icon: Icon(
                                        (isCurrentBook && playProvider.isPlaying)
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                      ),
                                      label: Text(
                                        isCurrentBook
                                            ? (playProvider.isPlaying ? '暂停播放' : '继续播放')
                                            : '开始收听',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // 章节可滑动列表
                            Expanded(
                              child: detailedBook.chapters.isEmpty
                                  ? const Center(child: Text('暂无章节信息'))
                                  : Consumer<PlaybackProvider>(
                                      builder: (context, playProvider, _) {
                                        final isCurrentBook = playProvider.currentBook?.id == detailedBook.id;

                                        return ListView.builder(
                                          itemCount: detailedBook.chapters.length,
                                          itemBuilder: (context, index) {
                                            final chapter = detailedBook.chapters[index];
                                            
                                            // 高亮逻辑：播放的书是这本书，并且章节 ID 一致
                                            final isPlayingChapter = isCurrentBook && 
                                                playProvider.currentChapter?.id == chapter.id;

                                            return ListTile(
                                              leading: isPlayingChapter
                                                  ? Icon(Icons.volume_up, color: colorScheme.primary)
                                                  : Text('${index + 1}', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                                              title: Text(
                                                chapter.title,
                                                style: TextStyle(
                                                  fontWeight: isPlayingChapter ? FontWeight.bold : FontWeight.normal,
                                                  color: isPlayingChapter ? colorScheme.primary : colorScheme.onSurface,
                                                ),
                                              ),
                                              trailing: Text(_formatDuration(chapter.duration), style: const TextStyle(fontSize: 12)),
                                              selected: isPlayingChapter,
                                              onTap: () {
                                                playProvider.playBook(detailedBook, startFromSeconds: chapter.start);
                                                showDialog(
                                                  context: context,
                                                  builder: (_) => const FullPlayerDialog(),
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // 底部迷你播放器栏，确保在详情页播放时也有清晰的视觉反馈
          Consumer<PlaybackProvider>(
            builder: (context, playProvider, _) {
              if (playProvider.currentBook != null) {
                return const MiniPlayerBar();
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}

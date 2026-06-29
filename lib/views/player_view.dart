import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/playback_provider.dart';
import '../services/storage_service.dart';

// 格式化时间显示 (秒 -> mm:ss 或 hh:mm:ss)
String _formatTime(Duration duration) {
  final int totalSeconds = duration.inSeconds;
  final int h = (totalSeconds / 3600).floor();
  final int m = ((totalSeconds % 3600) / 60).floor();
  final int s = totalSeconds % 60;
  
  final String sStr = s.toString().padLeft(2, '0');
  final String mStr = m.toString().padLeft(2, '0');
  
  if (h > 0) {
    return '$h:$mStr:$sStr';
  }
  return '$mStr:$sStr';
}

// 1. 底部迷你播放器栏
class MiniPlayerBar extends StatelessWidget {
  final VoidCallback? onTap;
  const MiniPlayerBar({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final playProvider = context.watch<PlaybackProvider>();
    final book = playProvider.currentBook;
    if (book == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final storage = context.read<StorageService>();
    final baseUrl = storage.getServerUrl() ?? '';
    final token = storage.getToken() ?? '';
    final userAgent = storage.getCustomUA();

    final progress = playProvider.duration.inSeconds > 0
        ? playProvider.position.inSeconds / playProvider.duration.inSeconds
        : 0.0;

    return InkWell(
      onTap: onTap ?? () {
        // 默认弹出完整控制面板
        showDialog(
          context: context,
          builder: (_) => const FullPlayerDialog(),
        );
      },
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.9),
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
        ),
        child: Column(
          children: [
            // 最顶部的极细进度指示条
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    // 封面
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: book.getCoverUrl(baseUrl),
                        httpHeaders: {
                          'User-Agent': userAgent,
                          'Authorization': 'Bearer $token',
                        },
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 38,
                          height: 38,
                          color: colorScheme.surface,
                          child: const Icon(Icons.book, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // 书名与章节
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            playProvider.currentChapter?.title ?? '正在加载章节...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    
                    // 倍速菜单按钮
                    TextButton(
                      onPressed: () {
                        _showSpeedMenu(context, playProvider);
                      },
                      child: Text('${playProvider.playbackRate.toStringAsFixed(2)}x'),
                    ),
                    
                    // 快退 10s
                    IconButton(
                      icon: const Icon(Icons.replay_10),
                      iconSize: 22,
                      onPressed: () {
                        final target = playProvider.position - const Duration(seconds: 10);
                        playProvider.seek(target < Duration.zero ? Duration.zero : target);
                      },
                    ),

                    // 播放/暂停
                    playProvider.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: Icon(playProvider.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                            iconSize: 36,
                            color: colorScheme.primary,
                            onPressed: () {
                              playProvider.playOrPause();
                            },
                          ),

                    // 快进 10s
                    IconButton(
                      icon: const Icon(Icons.forward_10),
                      iconSize: 22,
                      onPressed: () {
                        final target = playProvider.position + const Duration(seconds: 10);
                        playProvider.seek(target > playProvider.duration ? playProvider.duration : target);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedMenu(BuildContext context, PlaybackProvider provider) {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
    showMenu<double>(
      context: context,
      position: const RelativeRect.fromLTRB(100, 100, 24, 64),
      items: speeds.map((speed) {
        return PopupMenuItem<double>(
          value: speed,
          child: Row(
            children: [
              if (provider.playbackRate == speed)
                const Icon(Icons.check, size: 16)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Text('${speed.toStringAsFixed(2)}x'),
            ],
          ),
        );
      }).toList(),
    ).then((selectedSpeed) {
      if (selectedSpeed != null) {
        provider.setSpeed(selectedSpeed);
      }
    });
  }
}

// 2. 主播放面板 (共享控制核心组件，平铺或弹窗均可)
class PlayerMainPanel extends StatefulWidget {
  final bool showCloseButton;
  const PlayerMainPanel({super.key, this.showCloseButton = false});

  @override
  State<PlayerMainPanel> createState() => _PlayerMainPanelState();
}

class _PlayerMainPanelState extends State<PlayerMainPanel> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final playProvider = context.watch<PlaybackProvider>();
    final book = playProvider.currentBook;
    if (book == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final storage = context.read<StorageService>();
    final baseUrl = storage.getServerUrl() ?? '';
    final token = storage.getToken() ?? '';
    final userAgent = storage.getCustomUA();

    // 计算显示数值
    final durationSeconds = playProvider.duration.inSeconds.toDouble();
    final positionSeconds = playProvider.position.inSeconds.toDouble();
    final sliderValue = (_dragValue ?? positionSeconds).clamp(0.0, durationSeconds > 0 ? durationSeconds : 1.0);

    return Row(
      children: [
        // 左侧：超大封面
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.15),
            ),
            child: Center(
              child: AspectRatio(
                aspectRatio: 0.65,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: book.getCoverUrl(baseUrl),
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
                        child: const Icon(Icons.book, size: 80),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        
        // 右侧：控制面板
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 关闭按钮
                if (widget.showCloseButton)
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  )
                else
                  const SizedBox(height: 48),
                const Spacer(),

                // 书名与作者
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '作者: ${book.author} | 朗读: ${book.narrator}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                
                // 当前章节信息
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.volume_up, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          playProvider.currentChapter?.title ?? '未知章节',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // 进度条 Slider
                Slider(
                  value: sliderValue,
                  max: durationSeconds > 0 ? durationSeconds : 1.0,
                  onChanged: (val) {
                    setState(() {
                      _dragValue = val;
                    });
                  },
                  onChangeEnd: (val) async {
                    await playProvider.seek(Duration(seconds: val.toInt()));
                    setState(() {
                      _dragValue = null;
                    });
                  },
                ),
                
                // 时间显示
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatTime(Duration(seconds: sliderValue.toInt()))),
                    Text(_formatTime(playProvider.duration)),
                  ],
                ),
                const Spacer(),

                // 播放控制键
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 快退 10s
                    IconButton(
                      icon: const Icon(Icons.replay_10),
                      iconSize: 28,
                      onPressed: () {
                        final target = playProvider.position - const Duration(seconds: 10);
                        playProvider.seek(target < Duration.zero ? Duration.zero : target);
                      },
                    ),
                    const SizedBox(width: 16),
                    
                    // 播放/暂停
                    playProvider.isLoading
                        ? const SizedBox(
                            width: 56,
                            height: 56,
                            child: CircularProgressIndicator(),
                          )
                        : IconButton(
                            icon: Icon(playProvider.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                            iconSize: 64,
                            color: colorScheme.primary,
                            onPressed: () {
                              playProvider.playOrPause();
                            },
                          ),
                    const SizedBox(width: 16),

                    // 快进 10s
                    IconButton(
                      icon: const Icon(Icons.forward_10),
                      iconSize: 28,
                      onPressed: () {
                        final target = playProvider.position + const Duration(seconds: 10);
                        playProvider.seek(target > playProvider.duration ? playProvider.duration : target);
                      },
                    ),
                  ],
                ),
                const Spacer(),

                // 快速倍速调节
                const Text('倍速调节', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0].map((speed) {
                      final isSelected = playProvider.playbackRate == speed;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text('${speed.toStringAsFixed(2)}x'),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              playProvider.setSpeed(speed);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// 3. 弹出式大播放器 Dialog
class FullPlayerDialog extends StatelessWidget {
  const FullPlayerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final playProvider = context.watch<PlaybackProvider>();
    final book = playProvider.currentBook;
    if (book == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Container(
        width: 800,
        height: 600,
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.3)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: const PlayerMainPanel(showCloseButton: true),
        ),
      ),
    );
  }
}

// 4. 常驻的播放器主页面 Page Widget (用于 NavigationRail 选项卡)
class PlayerPageView extends StatelessWidget {
  const PlayerPageView({super.key});

  @override
  Widget build(BuildContext context) {
    final playProvider = context.watch<PlaybackProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    
    if (playProvider.currentBook == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 64,
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '当前暂无播放内容',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请在“书架”或“歌单”中选择曲目开始收听',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860, maxHeight: 600),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withOpacity(0.3),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: const PlayerMainPanel(showCloseButton: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

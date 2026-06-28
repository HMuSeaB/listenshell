import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import '../models/book.dart';
import '../models/chapter.dart';

class PlaybackProvider extends ChangeNotifier {
  final ApiService _apiService;
  final AudioService _audioService;
  final StorageService _storageService;

  Book? _currentBook;
  Chapter? _currentChapter;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _playbackRate = 1.0;
  bool _isLoading = false;
  String? _sessionId;

  // 定时进度同步
  Timer? _syncTimer;
  double _accumulatedTimeListened = 0.0;
  Duration _lastPosition = Duration.zero;

  // 各类状态流的订阅
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _rateSub;

  PlaybackProvider(this._apiService, this._audioService, this._storageService) {
    _initSubscriptions();
  }

  Book? get currentBook => _currentBook;
  Chapter? get currentChapter => _currentChapter;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  double get playbackRate => _playbackRate;
  bool get isLoading => _isLoading;

  void _initSubscriptions() {
    // 监听播放位置改变
    _posSub = _audioService.positionStream.listen((pos) {
      if (_currentBook == null) return;
      
      // 累加实际收听时间，过滤掉拖动 (Seek)
      final diff = (pos - _lastPosition).inMilliseconds.abs();
      if (diff < 1500) { // 如果间隔在一秒左右，属于正常播放，累加
        _accumulatedTimeListened += diff / 1000.0;
      }
      _lastPosition = pos;
      _position = pos;

      // 判定当前所属章节
      _updateCurrentChapter(pos.inSeconds.toDouble());
      notifyListeners();
    });

    // 监听音频总时长改变
    _durSub = _audioService.durationStream.listen((dur) {
      _duration = dur;
      notifyListeners();
    });

    // 监听播放/暂停状态
    _playingSub = _audioService.playingStream.listen((playing) {
      _isPlaying = playing;
      if (playing) {
        _startSyncTimer();
      } else {
        _stopSyncTimer();
        // 暂停时立刻同步一次进度
        _syncProgressImmediately();
      }
      notifyListeners();
    });

    // 监听倍速状态
    _rateSub = _audioService.rateStream.listen((rate) {
      _playbackRate = rate;
      notifyListeners();
    });
  }

  // 根据当前播放位置判定章节
  void _updateCurrentChapter(double currentSeconds) {
    if (_currentBook == null || _currentBook!.chapters.isEmpty) return;

    Chapter? foundChapter;
    for (final chapter in _currentBook!.chapters) {
      if (currentSeconds >= chapter.start && currentSeconds <= chapter.end) {
        foundChapter = chapter;
        break;
      }
    }
    
    // 如果没有精确匹配，默认取最后一个或第一个
    foundChapter ??= _currentBook!.chapters.first;

    if (_currentChapter?.id != foundChapter.id) {
      _currentChapter = foundChapter;
      notifyListeners();
    }
  }

  // 播放一本书
  Future<void> playBook(Book book, {double? startFromSeconds}) async {
    _isLoading = true;
    _currentBook = book;
    _currentChapter = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _lastPosition = Duration.zero;
    _accumulatedTimeListened = 0.0;
    notifyListeners();

    try {
      // 1. 创建播放会话 (Session)
      final sessionResult = await _apiService.startPlaySession(book.id);
      if (sessionResult == null) {
        throw Exception('无法建立播放会话');
      }

      _sessionId = sessionResult['id'] as String?;
      final audioTracks = sessionResult['audioTracks'] as List<dynamic>?;
      if (audioTracks == null || audioTracks.isEmpty) {
        throw Exception('服务端没有找到对应的音轨');
      }

      // 进度定位优先级: 参数指定 > 服务端历史进度
      double seekTo = 0.0;
      if (startFromSeconds != null) {
        seekTo = startFromSeconds;
      } else if (sessionResult['currentTime'] != null) {
        seekTo = (sessionResult['currentTime'] as num).toDouble();
      }

      // 2. 拼接完整的媒体流播放地址
      final relativePath = audioTracks[0]['contentUrl'] as String;
      final baseUrl = _storageService.getServerUrl() ?? '';
      final streamUrl = '$baseUrl$relativePath';

      // 3. 打开流音频 (传递伪装 Headers)
      final userAgent = _storageService.getCustomUA();
      final token = _storageService.getToken();
      
      await _audioService.openUrl(streamUrl, userAgent: userAgent, token: token);
      
      // 4. 跳转至指定进度，并应用之前的倍速
      if (seekTo > 0.0) {
        await _audioService.seek(Duration(seconds: seekTo.toInt()));
      }
      await _audioService.setSpeed(_playbackRate);

      developer.log('Successfully started session $_sessionId for book: ${book.title}', name: 'PlaybackProvider');
    } catch (e) {
      developer.log('Play book failed', error: e, name: 'PlaybackProvider');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 基础控制 API
  Future<void> play() async => await _audioService.play();
  Future<void> pause() async => await _audioService.pause();
  Future<void> playOrPause() async => await _audioService.playOrPause();
  
  Future<void> seek(Duration pos) async {
    _lastPosition = pos; // 避免把 Seek 造成的进度跃变计入收听时间
    await _audioService.seek(pos);
  }

  Future<void> setSpeed(double speed) async {
    _playbackRate = speed;
    await _audioService.setSpeed(speed);
    notifyListeners();
  }

  // 跳转到指定章节播放
  Future<void> playChapter(Chapter chapter) async {
    await seek(Duration(seconds: chapter.start.toInt()));
  }

  // 启动周期进度同步计时器 (每 10 秒)
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _syncProgressImmediately();
    });
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  // 立即同步进度到服务端
  Future<void> _syncProgressImmediately() async {
    final bookId = _currentBook?.id;
    final sId = _sessionId;
    if (bookId == null || sId == null || _accumulatedTimeListened <= 0.0) return;

    final curTime = _position.inSeconds.toDouble();
    final totalDur = _duration.inSeconds.toDouble();
    final timeListened = _accumulatedTimeListened;
    
    // 上报前先重置计时，防止并发上报冲突
    _accumulatedTimeListened = 0.0;

    await _apiService.syncPlaybackProgress(
      bookId: bookId,
      sessionId: sId,
      currentTime: curTime,
      timeListened: timeListened,
      duration: totalDur > 0 ? totalDur : (currentBook?.duration ?? 0.0),
      playbackRate: _playbackRate,
    );
  }

  @override
  void dispose() {
    _stopSyncTimer();
    _posSub?.cancel();
    _durSub?.cancel();
    _playingSub?.cancel();
    _rateSub?.cancel();
    _audioService.dispose();
    super.dispose();
  }
}

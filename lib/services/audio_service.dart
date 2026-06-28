import 'dart:async';
import 'dart:developer' as developer;
import 'package:media_kit/media_kit.dart';

class AudioService {
  late final Player _player;

  // 提供给外界的状态广播 Stream
  Stream<Duration> get positionStream => _player.stream.position;
  Stream<Duration> get durationStream => _player.stream.duration;
  Stream<bool> get playingStream => _player.stream.playing;
  Stream<double> get rateStream => _player.stream.rate;

  AudioService() {
    try {
      _player = Player();
      developer.log('media_kit Player initialized successfully.', name: 'AudioService');
    } catch (e) {
      developer.log('Initialize media_kit Player failed', error: e, name: 'AudioService');
    }
  }

  // 播放
  Future<void> play() async {
    try {
      await _player.play();
    } catch (e) {
      developer.log('Play command failed', error: e, name: 'AudioService');
    }
  }

  // 暂停
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      developer.log('Pause command failed', error: e, name: 'AudioService');
    }
  }

  // 播放/暂停切换
  Future<void> playOrPause() async {
    try {
      await _player.playOrPause();
    } catch (e) {
      developer.log('PlayOrPause command failed', error: e, name: 'AudioService');
    }
  }

  // 进度跳转
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      developer.log('Seek command failed', error: e, name: 'AudioService');
    }
  }

  // 设置播放速度 (支持极其稳定的倍速)
  Future<void> setSpeed(double speed) async {
    try {
      await _player.setRate(speed);
      developer.log('Playback rate set to: ${speed}x', name: 'AudioService');
    } catch (e) {
      developer.log('Set speed failed', error: e, name: 'AudioService');
    }
  }

  // 设置音量 (0 ~ 100)
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume);
    } catch (e) {
      developer.log('Set volume failed', error: e, name: 'AudioService');
    }
  }

  // 播放音频 URL，且必须带上 UA 伪装和 Auth Header，以防 mpv 请求流时暴露或被禁
  Future<void> openUrl(String url, {required String userAgent, String? token}) async {
    try {
      final headers = <String, String>{
        'User-Agent': userAgent,
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      developer.log('Opening source URL with custom User-Agent spoofing.', name: 'AudioService');
      
      await _player.open(
        Media(
          url,
          httpHeaders: headers,
        ),
        play: true, // 加载完成后直接播放
      );
    } catch (e) {
      developer.log('Open audio URL failed', error: e, name: 'AudioService');
    }
  }

  // 销毁播放器
  Future<void> dispose() async {
    try {
      await _player.dispose();
      developer.log('media_kit Player disposed.', name: 'AudioService');
    } catch (e) {
      developer.log('Dispose Player failed', error: e, name: 'AudioService');
    }
  }

  // 常规状态获取
  Duration get currentPosition => _player.state.position;
  Duration get totalDuration => _player.state.duration;
  bool get isPlaying => _player.state.playing;
  double get currentRate => _player.state.rate;
}

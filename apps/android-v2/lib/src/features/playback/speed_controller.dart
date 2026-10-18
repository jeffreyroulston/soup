import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soup_core/soup_core.dart';
import 'package:video_player/video_player.dart';

import '../../platform.dart';

/// A [SoupVideoController] that can also change playback speed. soup_core's
/// interface has no speed API, so the v2 player carries its own.
abstract interface class SpeedControllable {
  Future<void> setSpeed(double speed);
}

class SpeedVideoControllerFactory implements SoupVideoControllerFactory {
  const SpeedVideoControllerFactory();

  @override
  SoupVideoController create(Uri uri, {Future<String>? subtitleVtt}) =>
      SpeedVideoController(uri, subtitleVtt: subtitleVtt);
}

class SpeedVideoController extends ChangeNotifier
    implements SoupVideoController, SpeedControllable {
  SpeedVideoController(Uri uri, {Future<String>? subtitleVtt})
    : _controller = VideoPlayerController.networkUrl(
        uri,
        closedCaptionFile: subtitleVtt?.then(WebVTTCaptionFile.new),
        // webOS's player rejects any VideoPlayerOptions (mixWithOthers is
        // unsupported), and has no background playback to opt out of.
        videoPlayerOptions: isWebos
            ? null
            : VideoPlayerOptions(
                allowBackgroundPlayback: false,
                mixWithOthers: false,
              ),
      ) {
    _controller.addListener(_sync);
  }

  final VideoPlayerController _controller;
  SoupVideoValue _value = const SoupVideoValue();

  @override
  SoupVideoValue get value => _value;

  void _sync() {
    final s = _controller.value;
    _value = SoupVideoValue(
      initialized: s.isInitialized,
      playing: s.isPlaying,
      buffering: s.isBuffering,
      position: s.position,
      duration: s.duration,
      aspectRatio: s.aspectRatio <= 0 ? 16 / 9 : s.aspectRatio,
      caption: s.caption.text,
      error: s.errorDescription,
    );
    notifyListeners();
  }

  @override
  Future<void> initialize() => _guard(_controller.initialize);

  @override
  Future<void> play() => _guard(_controller.play);

  @override
  Future<void> pause() => _guard(_controller.pause);

  @override
  Future<void> seekTo(Duration position) =>
      _guard(() => _controller.seekTo(position));

  @override
  Future<void> setSpeed(double speed) =>
      _guard(() => _controller.setPlaybackSpeed(speed));

  /// webOS destroys its player on a media error, so every later call fails
  /// with "Player not found". Report the media error that caused it instead.
  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } on PlatformException {
      final media = _controller.value.errorDescription;
      if (media != null) throw VideoMediaException(media);
      rethrow;
    }
  }

  @override
  Widget buildView() => isWebos
      ? ScreenSpace(child: VideoPlayer(_controller))
      : VideoPlayer(_controller);

  bool _closed = false;

  /// Safe to call more than once: a screen leaving mid-load and the load
  /// itself can both close the same player.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _controller.removeListener(_sync);
    await _controller.dispose();
    dispose();
  }
}

/// The platform player failed on the media itself (unreachable URL,
/// unsupported codec, …).
class VideoMediaException implements Exception {
  const VideoMediaException(this.message);
  final String message;

  @override
  String toString() => message;
}

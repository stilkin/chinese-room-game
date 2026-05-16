import 'dart:async';

import 'package:flutter/foundation.dart';

import '../db/database_service.dart';

/// Drives the Replay screen's playback. Holds the current ply, the speed
/// factor, and the play loop's timer. The frames list is the post-inversion,
/// player-as-`+1` view of the game; the screen does the `flipPerspective`
/// once at load time and constructs the controller with the result.
class ReplayController extends ChangeNotifier {
  ReplayController({
    required this.frames,
    int? initialPly,
    Duration baseTick = const Duration(milliseconds: 600),
  }) : totalPlies = frames.length,
       _ply = (initialPly ?? frames.length).clamp(0, frames.length),
       _baseTick = baseTick;

  final List<ReplayFrame> frames;
  final int totalPlies;
  final Duration _baseTick;

  int _ply;
  double _speedFactor = 1.0;
  bool _isPlaying = false;
  Timer? _ticker;

  int get ply => _ply;
  double get speedFactor => _speedFactor;
  bool get isPlaying => _isPlaying;
  bool get isAtStart => _ply == 0;
  bool get isAtEnd => _ply >= totalPlies;

  void jumpToStart() {
    _stopTicker();
    _setPly(0);
  }

  void jumpToEnd() {
    _stopTicker();
    _setPly(totalPlies);
  }

  void stepBack() {
    _stopTicker();
    _setPly(_ply - 1);
  }

  void stepForward() {
    _stopTicker();
    _setPly(_ply + 1);
  }

  void seek(int p) {
    _stopTicker();
    _setPly(p);
  }

  void togglePlay() {
    if (_isPlaying) {
      _stopTicker();
      notifyListeners();
    } else {
      _play();
    }
  }

  /// Allowed playback multipliers; the speed row in the UI offers one button
  /// per entry so the user can jump directly to the speed they want. Includes
  /// a sub-1× option so the player can savour the moves of a long replay.
  static const List<double> speedFactors = [0.5, 1.0, 2.0, 3.0, 4.0];

  /// Sets the playback speed directly. If the ticker is running, restart it
  /// at the new tempo so the change feels immediate. Silently ignored if
  /// [factor] isn't one of [speedFactors] (callers should always pick from
  /// the canonical list).
  void setSpeed(double factor) {
    if (!speedFactors.contains(factor)) return;
    if (factor == _speedFactor) return;
    _speedFactor = factor;
    if (_isPlaying) {
      _ticker?.cancel();
      _startTicker();
    }
    notifyListeners();
  }

  void _play() {
    // If we're at the end, restart from the beginning so the play button
    // doesn't feel dead. Standard behaviour for video players.
    if (_ply >= totalPlies) _ply = 0;
    _isPlaying = true;
    _startTicker();
    notifyListeners();
  }

  void _startTicker() {
    final ms = (_baseTick.inMilliseconds / _speedFactor).round();
    _ticker = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (_ply >= totalPlies) {
        _stopTicker();
        notifyListeners();
        return;
      }
      _ply++;
      notifyListeners();
    });
  }

  void _stopTicker() {
    _isPlaying = false;
    _ticker?.cancel();
    _ticker = null;
  }

  void _setPly(int p) {
    final clamped = p.clamp(0, totalPlies);
    if (clamped == _ply) return;
    _ply = clamped;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:pi_ying/src/state/replay_controller.dart';

ReplayFrame _frame(int move) => (board: Board(13, 13), movePlayed: move);

void main() {
  group('ReplayController bounds & seek', () {
    test('defaults initialPly to totalPlies (opens at end)', () {
      final c = ReplayController(frames: [_frame(1), _frame(2), _frame(3)]);
      expect(c.totalPlies, 3);
      expect(c.ply, 3);
      expect(c.isAtEnd, isTrue);
      expect(c.isAtStart, isFalse);
    });

    test('initialPly clamps into [0, totalPlies]', () {
      final c = ReplayController(frames: [_frame(1)], initialPly: 99);
      expect(c.ply, 1);
      final c2 = ReplayController(frames: [_frame(1)], initialPly: -5);
      expect(c2.ply, 0);
    });

    test('stepBack and stepForward clamp at bounds', () {
      final c = ReplayController(frames: [_frame(1), _frame(2)], initialPly: 0);
      c.stepBack();
      expect(c.ply, 0);
      c.stepForward();
      expect(c.ply, 1);
      c.stepForward();
      expect(c.ply, 2);
      c.stepForward();
      expect(c.ply, 2);
    });

    test('jumpToStart / jumpToEnd', () {
      final c = ReplayController(frames: List.generate(5, _frame));
      c.jumpToStart();
      expect(c.ply, 0);
      c.jumpToEnd();
      expect(c.ply, 5);
    });

    test('seek clamps to bounds', () {
      final c = ReplayController(frames: [_frame(1), _frame(2), _frame(3)]);
      c.seek(-1);
      expect(c.ply, 0);
      c.seek(999);
      expect(c.ply, 3);
      c.seek(2);
      expect(c.ply, 2);
    });
  });

  group('ReplayController speed selection', () {
    test('setSpeed jumps to the requested factor', () {
      final c = ReplayController(frames: [_frame(1)]);
      expect(c.speedFactor, 1.0);
      c.setSpeed(3.0);
      expect(c.speedFactor, 3.0);
      c.setSpeed(0.5);
      expect(c.speedFactor, 0.5);
      c.setSpeed(1.0);
      expect(c.speedFactor, 1.0);
    });

    test('setSpeed silently rejects values outside the canonical list', () {
      final c = ReplayController(frames: [_frame(1)]);
      c.setSpeed(2.5);
      expect(c.speedFactor, 1.0);
      c.setSpeed(99.0);
      expect(c.speedFactor, 1.0);
    });

    test('speedFactors exposes the canonical list', () {
      expect(ReplayController.speedFactors, [0.5, 1.0, 2.0, 3.0, 4.0]);
    });
  });

  group('ReplayController play loop', () {
    test('togglePlay advances ply on each tick', () async {
      final c = ReplayController(
        frames: List.generate(5, _frame),
        initialPly: 0,
        baseTick: const Duration(milliseconds: 10),
      );
      c.togglePlay();
      expect(c.isPlaying, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(c.ply, greaterThan(0));
      c.togglePlay();
      expect(c.isPlaying, isFalse);
      c.dispose();
    });

    test('playback pauses at end automatically', () async {
      final c = ReplayController(
        frames: List.generate(2, _frame),
        initialPly: 0,
        baseTick: const Duration(milliseconds: 5),
      );
      c.togglePlay();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.isAtEnd, isTrue);
      expect(c.isPlaying, isFalse);
      c.dispose();
    });

    test('togglePlay from end restarts from start', () {
      final c = ReplayController(frames: List.generate(3, _frame));
      expect(c.isAtEnd, isTrue);
      c.togglePlay();
      // Starts from ply 0, not stuck at end.
      expect(c.ply, 0);
      expect(c.isPlaying, isTrue);
      c.dispose();
    });

    test('stepForward stops the ticker', () async {
      final c = ReplayController(
        frames: List.generate(5, _frame),
        initialPly: 0,
        baseTick: const Duration(milliseconds: 10),
      );
      c.togglePlay();
      expect(c.isPlaying, isTrue);
      c.stepForward();
      expect(c.isPlaying, isFalse);
      final plyAfterStop = c.ply;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Ticker is dead — ply should not have moved further.
      expect(c.ply, plyAfterStop);
      c.dispose();
    });

    test('setSpeed mid-play restarts ticker at new tempo', () async {
      final c = ReplayController(
        frames: List.generate(100, _frame),
        initialPly: 0,
        baseTick: const Duration(milliseconds: 100),
      );
      c.togglePlay();
      c.setSpeed(2.0);
      expect(c.speedFactor, 2.0);
      expect(c.isPlaying, isTrue);
      // No assertion on exact ply — just that toggling speed while playing
      // doesn't crash and leaves the controller in a sane state.
      c.dispose();
    });
  });
}

import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../app_scope.dart';
import '../db/database_service.dart';
import '../state/replay_controller.dart';
import '../theme.dart';
import '../widgets/go_board.dart';

class ReplayScreen extends StatefulWidget {
  final RecentGame game;

  /// When non-null, skips the DB load and uses these frames directly.
  /// Used by widget tests so they can drive the screen without booting a
  /// real database. Frames are assumed to already be player-as-`+1`
  /// (i.e. caller applied any necessary `flipPerspective`).
  final List<ReplayFrame>? frames;

  const ReplayScreen({super.key, required this.game, this.frames});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  ReplayController? _controller;
  int _rows = 0;
  int _cols = 0;
  late final int _passMove;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.frames != null) {
      _bootController(widget.frames!);
    } else {
      // Schedule the DB load for after first frame so `context` is safe
      // for the InheritedWidget read.
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFrames());
    }
  }

  void _bootController(List<ReplayFrame> frames) {
    if (frames.isEmpty) {
      _loadError = 'No moves recorded for this game.';
      return;
    }
    final first = frames.first.board;
    _rows = first.rows;
    _cols = first.cols;
    _passMove = _cols * _cols;
    _controller = ReplayController(frames: frames);
  }

  Future<void> _loadFrames() async {
    try {
      final db = AppScope.of(context).db;
      final raw = await db.loadGameForReplay(widget.game.gameId);
      if (!mounted) return;
      if (raw.isEmpty) {
        setState(() => _loadError = 'No moves recorded for this game.');
        return;
      }
      // Bot-won game: stored boards are sign-flipped (winner-POV). Apply
      // flipPerspective once so the player always renders as `+1` (ivory).
      final frames = widget.game.outcome == -1
          ? [
              for (final f in raw)
                (board: flipPerspective(f.board), movePlayed: f.movePlayed),
            ]
          : raw;
      setState(() => _bootController(frames));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load replay: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_verdict(widget.game.outcome))),
      body: SafeArea(
        // Bottom only — the appBar already handles the top safe area.
        top: false,
        child: _loadError != null
            ? Center(child: Text(_loadError!))
            : _controller == null
            ? const Center(child: CircularProgressIndicator())
            : _ReplayBody(
                controller: _controller!,
                game: widget.game,
                rows: _rows,
                cols: _cols,
                passMove: _passMove,
              ),
      ),
    );
  }
}

String _verdict(int outcome) => switch (outcome) {
  1 => 'YOU WIN',
  -1 => 'CLONE WINS',
  0 => 'DRAW',
  _ => 'GAME OVER',
};

class _ReplayBody extends StatelessWidget {
  final ReplayController controller;
  final RecentGame game;
  final int rows;
  final int cols;
  final int passMove;

  const _ReplayBody({
    required this.controller,
    required this.game,
    required this.rows,
    required this.cols,
    required this.passMove,
  });

  bool _isPass(int move) => move == passMove;

  ({int row, int col}) _lastMove(int ply) {
    if (ply == 0) return (row: -1, col: -1);
    final move = controller.frames[ply - 1].movePlayed;
    if (_isPass(move)) return (row: -1, col: -1);
    return (row: move ~/ cols, col: move % cols);
  }

  Board _board(int ply) {
    if (ply == 0) return Board(rows, cols);
    return controller.frames[ply - 1].board;
  }

  bool _currentIsPass() {
    if (controller.ply == 0) return false;
    return _isPass(controller.frames[controller.ply - 1].movePlayed);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ply = controller.ply;
        final total = controller.totalPlies;
        final last = _lastMove(ply);
        final passSuffix = _currentIsPass() ? ' (pass)' : '';
        final hasArea = game.playerArea != null && game.cloneArea != null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasArea)
                Text(
                  'AREA  ·  YOU ${game.playerArea}  ·  CLONE ${game.cloneArea}',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: PiYingTheme.onSurfaceMuted,
                  ),
                ),
              const SizedBox(height: 4),
              // Board shrinks to fit available height; controls below stay
              // visible without scrolling on any sensible phone aspect ratio.
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: GoBoard(
                      board: _board(ply),
                      lastMoveRow: last.row,
                      lastMoveCol: last.col,
                      // No onTap → read-only.
                      // Faster animation at 2×+ so it stays non-overlapping
                      // with the inter-move interval (300ms / 200ms / 150ms).
                      animationDuration: controller.speedFactor >= 2.0
                          ? const Duration(milliseconds: 60)
                          : const Duration(milliseconds: 120),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Move $ply / $total$passSuffix',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
              Slider(
                min: 0,
                max: total.toDouble(),
                value: ply.toDouble().clamp(0, total.toDouble()),
                divisions: total > 0 ? total : null,
                onChanged: (v) => controller.seek(v.round()),
              ),
              _VcrControls(controller: controller),
              const SizedBox(height: 4),
              _SpeedRow(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

class _SpeedRow extends StatelessWidget {
  final ReplayController controller;

  const _SpeedRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final factor in ReplayController.speedFactors)
          _SpeedButton(
            factor: factor,
            isActive: controller.speedFactor == factor,
            onTap: () => controller.setSpeed(factor),
          ),
      ],
    );
  }
}

class _SpeedButton extends StatelessWidget {
  final double factor;
  final bool isActive;
  final VoidCallback onTap;

  const _SpeedButton({
    required this.factor,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = factor == 0.5 ? '½×' : '${factor.toStringAsFixed(0)}×';
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive ? PiYingTheme.onSurface : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            color: isActive
                ? PiYingTheme.onSurface
                : PiYingTheme.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}

class _VcrControls extends StatelessWidget {
  final ReplayController controller;

  const _VcrControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: controller.isAtStart ? null : controller.jumpToStart,
          icon: const Icon(Icons.skip_previous),
          tooltip: 'Jump to start',
        ),
        IconButton(
          onPressed: controller.isAtStart ? null : controller.stepBack,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Step back',
        ),
        IconButton(
          onPressed: controller.togglePlay,
          icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
          tooltip: controller.isPlaying ? 'Pause' : 'Play',
        ),
        IconButton(
          onPressed: controller.isAtEnd ? null : controller.stepForward,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Step forward',
        ),
        IconButton(
          onPressed: controller.isAtEnd ? null : controller.jumpToEnd,
          icon: const Icon(Icons.skip_next),
          tooltip: 'Jump to end',
        ),
      ],
    );
  }
}

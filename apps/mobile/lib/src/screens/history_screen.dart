import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../db/database_service.dart';
import '../theme.dart';
import '../widgets/area_history_strip.dart';

class HistoryScreen extends StatelessWidget {
  /// When non-null, overrides the games shown. Defaults to reading the
  /// notifier's `recentGames`. The override is used by widget tests so they
  /// can render the screen without booting a real database.
  final List<RecentGame>? games;

  const HistoryScreen({super.key, this.games});

  @override
  Widget build(BuildContext context) {
    if (games != null) {
      return _buildBody(context, games!);
    }
    final notifier = AppScope.of(context);
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) => _buildBody(context, notifier.recentGames),
    );
  }

  Widget _buildBody(BuildContext context, List<RecentGame> games) {
    return Scaffold(
      appBar: AppBar(title: const Text('HISTORY')),
      body: Builder(
        builder: (context) {
          if (games.isEmpty) {
            return Center(
              child: Text(
                'No completed games yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PiYingTheme.onSurfaceMuted,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: games.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: PiYingTheme.outline),
            itemBuilder: (context, i) => _HistoryRow(
              game: games[i],
              onTap: () =>
                  Navigator.pushNamed(context, '/replay', arguments: games[i]),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final RecentGame game;
  final VoidCallback onTap;

  const _HistoryRow({required this.game, required this.onTap});

  // Fixed-width column for the area-split text so the proportion bar's right
  // edge lines up across rows regardless of digit count (e.g. "—" vs
  // "110 : 59").
  static const double _kAreaColumnWidth = 80;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final date = _formatStartedAt(game.startedAt);
    final hasArea = game.playerArea != null && game.cloneArea != null;
    final areaLabel = hasArea ? '${game.playerArea} : ${game.cloneArea}' : '—';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(date, style: textTheme.bodyMedium),
                  ),
                ),
                Expanded(
                  child: Center(child: _OutcomeChip(outcome: game.outcome)),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${game.totalMoves} moves',
                      style: textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 6,
                    child: CustomPaint(painter: _HistoryRowBarPainter(game)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: _kAreaColumnWidth,
                  child: Text(
                    areaLabel,
                    style: textTheme.bodySmall,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeChip extends StatelessWidget {
  final int outcome;

  const _OutcomeChip({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final (label, fg) = switch (outcome) {
      1 => ('WIN', PiYingTheme.onSurface),
      -1 => ('LOSS', PiYingTheme.onSurfaceMuted),
      0 => ('DRAW', PiYingTheme.lineColor),
      _ => ('—', PiYingTheme.onSurfaceMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: fg, width: 1)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}

class _HistoryRowBarPainter extends CustomPainter {
  final RecentGame game;

  _HistoryRowBarPainter(this.game);

  @override
  void paint(Canvas canvas, Size size) {
    paintAreaHistoryRow(
      canvas,
      Paint()..style = PaintingStyle.fill,
      Rect.fromLTWH(0, 0, size.width, size.height),
      game,
    );
  }

  @override
  bool shouldRepaint(_HistoryRowBarPainter old) => old.game != game;
}

/// Formats epoch milliseconds as "May 12 · 14:32" using only `DateTime`
/// (avoids pulling `intl` in as a direct dependency).
String _formatStartedAt(int epochMs) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day} · $hh:$mm';
}

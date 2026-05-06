import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  group('narrate', () {
    test('exactMatch includes game ID and moves', () {
      final text = narrate(
        DecisionContext.exactMatch,
        gameId: 'g5',
        movesToEnd: 3,
      );
      expect(text, contains('g5'));
      expect(text, contains('3'));
      expect(text.isNotEmpty, true);
    });

    test('exactMatch without movesToEnd still works', () {
      final text = narrate(DecisionContext.exactMatch, gameId: 'g5');
      expect(text, contains('g5'));
    });

    test('fuzzyMatch includes game ID', () {
      final text = narrate(DecisionContext.fuzzyMatch, gameId: 'g3');
      expect(text, contains('g3'));
    });

    test('multipleCandidates includes count', () {
      final text = narrate(
        DecisionContext.multipleCandidates,
        candidateCount: 4,
      );
      expect(text, contains('4'));
    });

    test('invertedData includes game ID', () {
      final text = narrate(DecisionContext.invertedData, gameId: 'g12');
      expect(text, contains('g12'));
    });

    test('fallbackUsed includes strategy name', () {
      final text = narrate(
        DecisionContext.fallbackUsed,
        fallbackName: 'middleFocus',
      );
      expect(text, contains('middleFocus'));
    });

    test('allLosing returns non-empty text', () {
      final text = narrate(DecisionContext.allLosing);
      expect(text.isNotEmpty, true);
    });

    test('every context produces non-empty narration', () {
      for (final ctx in DecisionContext.values) {
        final text = narrate(
          ctx,
          gameId: 'g1',
          movesToEnd: 3,
          candidateCount: 2,
          fallbackName: 'random',
        );
        expect(text.isNotEmpty, true, reason: '$ctx produced empty narration');
      }
    });
  });
}

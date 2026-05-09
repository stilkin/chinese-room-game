import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  group('narrate', () {
    test('fuzzyMatch is non-empty', () {
      final text = narrate(DecisionContext.fuzzyMatch);
      expect(text.isNotEmpty, true);
    });

    test('multipleCandidates includes count', () {
      final text = narrate(
        DecisionContext.multipleCandidates,
        candidateCount: 4,
      );
      expect(text, contains('4'));
    });

    test('multipleCandidates pluralises games', () {
      expect(
        narrate(DecisionContext.multipleCandidates, candidateCount: 1),
        contains('1 past game'),
      );
      expect(
        narrate(DecisionContext.multipleCandidates, candidateCount: 5),
        contains('5 past games'),
      );
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
        final text = narrate(ctx, candidateCount: 2, fallbackName: 'random');
        expect(text.isNotEmpty, true, reason: '$ctx produced empty narration');
      }
    });
  });
}

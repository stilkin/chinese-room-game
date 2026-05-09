enum DecisionContext { fuzzyMatch, multipleCandidates, fallbackUsed, allLosing }

String narrate(
  DecisionContext context, {
  int? candidateCount,
  String? fallbackName,
}) {
  switch (context) {
    case DecisionContext.fuzzyMatch:
      return 'this looks like a past game of yours — going with what worked';
    case DecisionContext.multipleCandidates:
      final n = candidateCount ?? 0;
      final games = n == 1 ? 'game' : 'games';
      return "i've seen positions like this in $n past $games — going with the best outcome";
    case DecisionContext.fallbackUsed:
      return "i've never seen anything like this — going with $fallbackName";
    case DecisionContext.allLosing:
      return 'everything i know about this position is bad — trying something different';
  }
}

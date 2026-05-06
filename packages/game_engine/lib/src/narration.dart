enum DecisionContext {
  exactMatch,
  fuzzyMatch,
  multipleCandidates,
  invertedData,
  fallbackUsed,
  allLosing,
}

String narrate(
  DecisionContext context, {
  String? gameId,
  int? movesToEnd,
  int? candidateCount,
  String? fallbackName,
}) {
  switch (context) {
    case DecisionContext.exactMatch:
      if (movesToEnd != null && movesToEnd > 0) {
        return 'Playing a move from game $gameId (won in $movesToEnd moves)';
      }
      return 'Playing a move from game $gameId';
    case DecisionContext.fuzzyMatch:
      return 'This looks like game $gameId — going with what worked';
    case DecisionContext.multipleCandidates:
      return "I've seen this $candidateCount times — going with the best outcome";
    case DecisionContext.invertedData:
      return 'Playing a move that was used against you in game $gameId';
    case DecisionContext.fallbackUsed:
      return "I've never seen anything like this — going with $fallbackName";
    case DecisionContext.allLosing:
      return 'Everything I know about this position is bad — trying something different';
  }
}

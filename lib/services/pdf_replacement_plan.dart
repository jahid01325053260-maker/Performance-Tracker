/// A pure, deterministic plan for replacing one officer's full report set.
/// The Firestore writer must commit all parts of this plan atomically.
class PdfReplacementPlan {
  PdfReplacementPlan(Set<String> existingIds, Set<String> incomingIds)
    : removedIds = existingIds.difference(incomingIds),
      insertedIds = incomingIds.difference(existingIds),
      overwrittenIds = incomingIds.intersection(existingIds),
      resultingCount = incomingIds.length;

  final Set<String> removedIds;
  final Set<String> insertedIds;
  final Set<String> overwrittenIds;
  final int resultingCount;

  // Backup + state + leaderboard are three additional writes.
  int get batchWriteCount =>
      removedIds.length + insertedIds.length + overwrittenIds.length + 3;
}

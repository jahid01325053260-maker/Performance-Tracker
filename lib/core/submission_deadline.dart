/// A report for a given year and month is due on the 10th of the NEXT month.
/// For December, the date is January 10 of the following year.
DateTime submissionDueDate(int year, int month) {
  if (year < 2000 || month < 1 || month > 12) {
    throw ArgumentError('Invalid report period');
  }
  return DateTime(year, month + 1, 10);
}

bool reminderIsDue(String reportingPeriod, DateTime now) {
  final parts = reportingPeriod.split('-');
  if (parts.length != 2) return false;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return false;
  final date = submissionDueDate(year, month);
  final today = DateTime(now.year, now.month, now.day);
  return !today.isBefore(date);
}

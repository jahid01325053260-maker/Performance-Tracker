/// Shared report year range, consistent across dashboards and exports.
const int firstReportYear = 2020;
const int lastReportYear = 2032;
final List<int> reportYears = List<int>.generate(
  lastReportYear - firstReportYear + 1, (index) => firstReportYear + index,
);

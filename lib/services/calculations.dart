import 'dart:math';
import '../models/entities.dart';

/// The one canonical card-count implementation used by dashboard, rankings and exports.
int countCards(Iterable<CardRecord> records, {String? employeeId, String? reportingPeriod}) {
  final keys = <String>{};
  for (final r in records) {
    if (!r.valid) continue;
    if (employeeId != null && r.employeeId.trim() != employeeId.trim()) continue;
    if (reportingPeriod != null && r.reportingPeriod != reportingPeriod) continue;
    keys.add('${r.employeeId.trim()}|${r.reportingPeriod}|${accountKey(r.accountNo)}');
  }
  return keys.length;
}

/// Count distinct eligible accounts across one reporting year. An account
/// can count in different months, but cannot count twice within one month.
int countCardsForYear(Iterable<CardRecord> records, String employeeId, int year) {
  return countCards(records.where((r) =>
      r.employeeId.trim() == employeeId.trim() &&
      r.reportingPeriod.startsWith('$year-')));
}

class Achievement {
  final int achieved, target;
  const Achievement(this.achieved, this.target);
  double? get percentage => target <= 0 ? null : achieved * 100 / target;
  bool get below50 => target > 0 && achieved * 2 < target;
  bool get atOrBelow50 => target > 0 && achieved * 2 <= target;
  int get needsFor50 => below50 ? max(0, (target / 2).ceil() - achieved) : 0;
  int get shortfall => max(0, target-achieved);
  String get label => percentage == null ? 'No Target Assigned' : '${percentage!.toStringAsFixed(1)}%';
  double get progress => percentage == null ? 0 : (percentage! / 100).clamp(0,1).toDouble();
}

List<RankingEntry> calculateRanking(Iterable<Employee> employees, Iterable<CardRecord> records) {
  final sorted = employees.where((e) => e.isOfficer && e.status.toLowerCase() == 'approved').toList()
    ..sort((a,b) {
      final diff = countCards(records, employeeId:b.employeeId) - countCards(records, employeeId:a.employeeId);
      if(diff != 0) return diff;
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return name != 0 ? name : a.employeeId.compareTo(b.employeeId);
    });
  return [for(var i=0; i<sorted.length; i++) RankingEntry(sorted[i], countCards(records, employeeId:sorted[i].employeeId), i+1)];
}

bool didSubmit(Iterable<CardRecord> records, String employeeId, String reportingPeriod) => records.any((r) =>
  r.employeeId == employeeId && r.reportingPeriod == reportingPeriod && r.status != 'deleted' && r.status != 'rejected');

/// Native Manager Team fallback for old records without managerId.
bool belongsToManager(Employee officer, Employee manager) =>
    officer.isOfficer && (
      (officer.managerId.isNotEmpty && officer.managerId == manager.employeeId) ||
      (officer.managerId.isEmpty && officer.salesManager.trim().toLowerCase() ==
        manager.name.trim().toLowerCase()));

/// True only for a valid numeric achievement percentage at or below 50%.
/// "No Target Assigned" is never styled as a low achievement.
bool isLowAchievementLabel(String value) {
  final label = value.trim();
  if (!label.endsWith('%')) return false;
  final percentage = double.tryParse(label.substring(0, label.length - 1).trim());
  return percentage != null && percentage >= 0 && percentage <= 50;
}

import 'package:intl/intl.dart';

String norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
String upper(String s) => norm(s).toUpperCase();
String accountKey(String account) => account.replaceAll(RegExp(r'[^0-9]'), '');
String periodOf(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}';
String readablePeriod(String period) {
  final p = DateTime.tryParse('$period-01');
  return p == null ? period : DateFormat('MMMM yyyy').format(p);
}
const monthNames = <String>['January','February','March','April','May','June','July','August','September','October','November','December'];

class Employee {
  final String employeeId, name, email, mobile, officialNumber, branch, zone, salesManager, managerId,
      department, role, status, profileImage;
  final int monthlyTarget, yearlyTarget;
  const Employee({required this.employeeId, required this.name, required this.role, required this.status,
    this.email='', this.mobile='', this.officialNumber='', this.branch='', this.zone='', this.salesManager='',
    this.managerId='', this.department='', this.profileImage='', this.monthlyTarget=0, this.yearlyTarget=0});
  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
    employeeId: '${j['employeeId'] ?? ''}', name: '${j['name'] ?? ''}', role: '${j['role'] ?? ''}'.trim().isEmpty ? 'USER' : '${j['role']}'.trim(),
    status: '${j['status'] ?? ''}', email: '${j['email'] ?? ''}', mobile: '${j['mobile'] ?? ''}',
    officialNumber: '${j['officialNumber'] ?? ''}', branch: '${j['branch'] ?? ''}', zone: '${j['zone'] ?? ''}',
    salesManager: '${j['salesManager'] ?? ''}', managerId: '${j['managerId'] ?? ''}',
    department: '${j['department'] ?? ''}', profileImage: '${j['profileImage'] ?? ''}',
    monthlyTarget: asInt(j['monthlyTarget']), yearlyTarget: asInt(j['yearlyTarget']));
  bool get isAdmin => role.toUpperCase() == 'ADMIN';
  bool get isOfficer => role.toUpperCase() == 'USER';
  bool get isManagement => !isOfficer && !isAdmin;
  String get displayBranch => upper(branch).isEmpty ? 'N/A' : upper(branch);
  String get displayZone => upper(zone).isEmpty ? 'N/A' : upper(zone);
}

int asInt(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

class CardRecord {
  final String id, employeeId, employeeName, applicantName, accountNo, limit, branch, zone, month, reportingPeriod, status, source, periodStart, periodEnd, originatingBranch, verify, managerId, salesManager;
  final int year, slNo;
  const CardRecord({required this.id, required this.employeeId, required this.employeeName, required this.applicantName,
    required this.accountNo, required this.limit, required this.reportingPeriod, this.status='confirmed',
    this.month='', this.year=0, this.branch='', this.zone='', this.slNo=0,
    this.source='manual', this.periodStart='', this.periodEnd='',
    this.originatingBranch='', this.verify='', this.managerId='', this.salesManager=''});
  factory CardRecord.fromJson(Map<String, dynamic> j) {
    final year = asInt(j['year']);
    final month = '${j['month'] ?? ''}';
    final date = DateTime.fromMillisecondsSinceEpoch(asInt(j['timestamp'] ?? 0) > 0 ? asInt(j['timestamp']) : DateTime.now().millisecondsSinceEpoch);
    final monthIndex = monthNames.indexWhere((m) => m.toLowerCase() == month.toLowerCase());
    final finalYear = year > 0 ? year : date.year;
    final finalMonth = monthIndex >= 0 ? monthIndex + 1 : date.month;
    final period = '${j['reportingPeriod'] ?? ''}'.isNotEmpty ? '${j['reportingPeriod']}' : '$finalYear-${finalMonth.toString().padLeft(2, '0')}';
    return CardRecord(id: '${j['id'] ?? ''}', employeeId: '${j['employeeId'] ?? ''}', employeeName: '${j['employeeName'] ?? ''}',
      applicantName: '${j['applicantName'] ?? ''}', accountNo: '${j['accountNo'] ?? ''}', limit: '${j['limit'] ?? ''}',
      reportingPeriod: period, month: month, year: finalYear, branch: '${j['branch'] ?? ''}', zone: '${j['zone'] ?? ''}', status: '${j['status'] ?? 'confirmed'}', source: '${j['source'] ?? 'manual'}',
      slNo: asInt(j['slNo']), periodStart: '${j['periodStart'] ?? ''}',
      periodEnd: '${j['periodEnd'] ?? ''}',
      originatingBranch: '${j['originatingBranch'] ?? ''}', verify: '${j['verify'] ?? ''}',
      managerId: '${j['managerId'] ?? ''}', salesManager: '${j['salesManager'] ?? ''}');
  }
  bool get isNil => limit.trim().toUpperCase() == 'NIL' || accountNo.trim().toUpperCase() == 'N/A';
  bool get valid => status != 'deleted' && status != 'rejected' && !isNil &&
      RegExp(r'^\d{4}906\d{6}$').hasMatch(accountKey(accountNo));
}

class EmployeeTarget {
  final String employeeId, reportingPeriod;
  final int targetCards, yearlyTargetCards;
  const EmployeeTarget({required this.employeeId, required this.reportingPeriod, required this.targetCards, this.yearlyTargetCards=0});
  factory EmployeeTarget.fromJson(Map<String,dynamic> j) {
    final y = asInt(j['year']);
    final m = monthNames.indexWhere((a) => a.toLowerCase() == '${j['month'] ?? ''}'.toLowerCase());
    return EmployeeTarget(employeeId: '${j['employeeId'] ?? ''}',
      reportingPeriod: '${j['reportingPeriod'] ?? (y > 0 && m >= 0 ? '$y-${(m+1).toString().padLeft(2,'0')}' : '')}',
      targetCards: asInt(j['targetCards']), yearlyTargetCards: asInt(j['yearlyTargetCards']));
  }
}

class RankingEntry {
  final Employee employee;
  final int cards, rank;
  const RankingEntry(this.employee, this.cards, this.rank);
}

/// Public name/id only; not an Employee with private fields.
class SalesManagerOption {
  final String employeeId, name;
  const SalesManagerOption({required this.employeeId, required this.name});
}

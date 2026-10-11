import '../models/entities.dart';

/// UI and export scope. Firestore Security Rules remain the authority.
/// Membership for PRIVATE reports uses a stable managerId. A legacy manager
/// display name is never sufficient to authorize access to applicant records.
bool canReadOfficerReports(Employee viewer, Employee officer) {
  if (!officer.isOfficer) return false;
  if (viewer.isAdmin || {'agm', 'dgm'}.contains(viewer.role.trim().toLowerCase())) return true;
  if (viewer.isOfficer) return viewer.employeeId == officer.employeeId;
  if (viewer.role.trim().toLowerCase() == 'sales manager') {
    return officer.managerId.isNotEmpty &&
        officer.managerId == viewer.employeeId;
  }
  return false;
}

List<Employee> permittedReportOfficers(Employee viewer, Iterable<Employee> people) =>
    people.where((e) => e.status.trim().toLowerCase() == 'approved' &&
        canReadOfficerReports(viewer, e)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// The annual target is assigned separately from the repeating monthly target.
/// A zero annual target means the annual target is not assigned.
int targetForSelection(Employee officer, {required bool allMonths}) =>
    allMonths ? officer.yearlyTarget : officer.monthlyTarget;

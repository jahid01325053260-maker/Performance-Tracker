import 'package:flutter_test/flutter_test.dart';
import 'package:performance_tracker_flutter/models/entities.dart';
import 'package:performance_tracker_flutter/services/calculations.dart';
void main() {
  test('Below 50 threshold boundaries',(){
    expect(Achievement(9,20).percentage,45);
    expect(Achievement(9,20).needsFor50,1);
    expect(Achievement(10,20).below50,false);
    expect(Achievement(21,20).percentage,105);
    expect(Achievement(0,0).percentage,isNull);
  });
  test('Distinct account in employee and month / year',(){
    const a=CardRecord(id:'1',employeeId:'000000000001',employeeName:'A',applicantName:'B',accountNo:'2706-906-000746',limit:'100',reportingPeriod:'2026-01');
    const b=CardRecord(id:'2',employeeId:'000000000001',employeeName:'A',applicantName:'B',accountNo:'2706 906 000746',limit:'100',reportingPeriod:'2026-01');
    const c=CardRecord(id:'3',employeeId:'000000000001',employeeName:'A',applicantName:'B',accountNo:'2706-906-000746',limit:'100',reportingPeriod:'2027-01');
    const nil=CardRecord(id:'4',employeeId:'000000000001',employeeName:'A',applicantName:'B',accountNo:'N/A',limit:'NIL',reportingPeriod:'2026-01');
    expect(countCards([a,b,c,nil]),2);
    const otherProduct=CardRecord(id:'5',employeeId:'000000000001',employeeName:'A',
      applicantName:'Other product',accountNo:'2706-379-000746',limit:'100',reportingPeriod:'2026-01');
    expect(countCards([a,b,c,nil,otherProduct]),2);
  });
  test('Soft-deleted account counts again only when confirmed', () {
    const removed = CardRecord(id: 'restored', employeeId: '000000000001',
      employeeName: 'Officer', applicantName: 'Applicant',
      accountNo: '2706-906-000746', limit: '100',
      reportingPeriod: '2026-09', status: 'deleted');
    const restored = CardRecord(id: 'restored', employeeId: '000000000001',
      employeeName: 'Officer', applicantName: 'Applicant',
      accountNo: '2706-906-000746', limit: '100',
      reportingPeriod: '2026-09', status: 'confirmed');
    expect(countCards([removed]), 0);
    expect(countCards([restored, restored]), 1);
  });
  test('Achievement red style threshold includes exactly 50 percent', () {
    expect(Achievement(10, 20).atOrBelow50, isTrue);
    expect(Achievement(9, 20).atOrBelow50, isTrue);
    expect(Achievement(11, 20).atOrBelow50, isFalse);
    expect(Achievement(0, 0).atOrBelow50, isFalse);
    expect(isLowAchievementLabel('50.0%'), isTrue);
    expect(isLowAchievementLabel('49.9%'), isTrue);
    expect(isLowAchievementLabel('50.1%'), isFalse);
    expect(isLowAchievementLabel('No Target Assigned'), isFalse);
  });
}

import test from 'node:test';
import assert from 'node:assert/strict';
import {achievement,countCards,canonicalAccount,recordPeriod} from '../src/logic.js';
test('threshold 9 of 20: below 50, one needed',()=>{
  assert.deepEqual(achievement(9,20),{achieved:9,target:20,percentage:45,below50:true,needsFor50:1,shortfall:11});
  assert.equal(achievement(10,20).below50,false);
  assert.equal(achievement(21,20).percentage,105);
  assert.equal(achievement(0,0).percentage,null);
});
test('NIL excluded; same month duplicates collapsed; years distinct',()=>{
  const base={employeeId:'000000000001',status:'confirmed',limit:'100',accountNo:'2706-906-000746'};
  assert.equal(countCards([
    {...base,reportingPeriod:'2026-01'},
    {...base,reportingPeriod:'2026-01'},
    {...base,reportingPeriod:'2027-01'},
    {...base,reportingPeriod:'2026-01',limit:'NIL'},
  ]),2);
});
test('906 account and legacy month conversion',()=>{
  assert.equal(canonicalAccount('2706 906 000746'),'2706-906-000746');
  assert.throws(()=>canonicalAccount('2706-905-000746'));
  assert.equal(recordPeriod({month:'January',year:2027}),'2027-01');
});

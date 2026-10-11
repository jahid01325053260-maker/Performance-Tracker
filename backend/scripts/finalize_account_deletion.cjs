/**
 * Finalize an ADMIN-confirmed pending deletion from the trusted PC ONLY.
 * This removes Auth access & directory identity; retains historical KPI
 * records for audit (consider retention policy separately).
 * NEVER ship Admin SDK credentials to Flutter/GitHub.
 * TARGET_EMPLOYEE_ID, FIREBASE_PROJECT_ID required.
 * APPLY=1 BACKUP_CONFIRMED=1 after exporting Firestore & confirming ID.
 */
const admin = require('firebase-admin');
const crypto = require('node:crypto');
const id = (process.env.TARGET_EMPLOYEE_ID || '').trim();
const projectId = process.env.FIREBASE_PROJECT_ID;
const apply = process.env.APPLY === '1' && process.env.BACKUP_CONFIRMED === '1';
if (!projectId || !/^\d{12}$/.test(id)) {
  throw new Error('Provide FIREBASE_PROJECT_ID and valid TARGET_EMPLOYEE_ID.');
}
admin.initializeApp({credential:admin.credential.applicationDefault(), projectId});
const db=admin.firestore();
const hash = crypto.createHash('sha256').update(id).digest('hex');
async function run() {
  const reqRef=db.collection('account_deletion_requests').doc(id);
  const request=(await reqRef.get()).data();
  const employee=(await db.collection('employees').doc(id).get()).data();
  if (!request || request.status !== 'Pending') throw new Error('No pending admin deletion request.');
  if (!employee || employee.status !== 'Disabled' ||
      !employee.authUid || request.authUid !== employee.authUid) {
    throw new Error('UID/status mismatch; stop and repair identity first.');
  }
  const identity=(await db.collection('auth_users').doc(employee.authUid).get()).data();
  if (!identity || identity.employeeId !== id || identity.status !== 'Disabled') {
    throw new Error('Auth identity mismatch. Refusing deletion.');
  }
  console.log(`${apply ? 'DELETE' : 'DRY RUN'}: employee=${id} uid=${employee.authUid}. Historic KPI retained.`);
  if (!apply) return;
  try { await admin.auth().deleteUser(employee.authUid); }
  catch(e) { if(e.code !== 'auth/user-not-found') throw e; }
  const batch=db.batch();
  batch.delete(db.collection('employees').doc(id));
  batch.delete(db.collection('auth_users').doc(employee.authUid));
  batch.delete(db.collection('login_index').doc(hash));
  batch.delete(db.collection('sales_manager_directory').doc(id));
  batch.delete(db.collection('leaderboard').doc(id));
  batch.set(reqRef,{status:'Completed',completedAt:admin.firestore.FieldValue.serverTimestamp()}, {merge:true});
  await batch.commit();
  console.log('Firebase Authentication account and directory ID deleted. Historic KPI records retained.');
}
run().catch(e=>{console.error(e);process.exitCode=1;});

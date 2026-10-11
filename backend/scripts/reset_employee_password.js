// Trusted local operator utility for Spark (Free) projects using a .invalid
// Firebase Auth email alias. Do NOT expose this as a client call or HTTP API.
// Only run after independently verifying the employee's identity.
import admin from 'firebase-admin';

const employeeId = (process.env.TARGET_EMPLOYEE_ID || '').trim();
const projectId = (process.env.FIREBASE_PROJECT_ID || '').trim();
const newPassword = process.env.NEW_EMPLOYEE_PASSWORD || '';
const apply = process.argv.includes('--apply');
if (!/^\d{12}$/.test(employeeId) || !projectId || (apply && newPassword.length < 12)) {
  console.error('Set FIREBASE_PROJECT_ID, TARGET_EMPLOYEE_ID (12 digits), and for --apply NEW_EMPLOYEE_PASSWORD (12+ characters).');
  process.exit(1);
}
admin.initializeApp({
  credential: admin.credential.applicationDefault(), projectId,
});
try {
  const db = admin.firestore();
  const employeeDoc = await db.collection('employees').doc(employeeId).get();
  if (!employeeDoc.exists) throw new Error('Employee not found.');
  const employee = employeeDoc.data();
  if (!employee.authUid) throw new Error('Employee is not linked to Firebase Auth.');
  const identityDoc = await db.collection('auth_users').doc(employee.authUid).get();
  if (!identityDoc.exists || identityDoc.data().employeeId !== employeeId) {
    throw new Error('Auth identity mismatch. Resolve first; no password changed.');
  }
  const user = await admin.auth().getUser(employee.authUid);
  if (!user.email) throw new Error('Firebase Auth account has no sign-in email.');
  if (!apply) {
    console.log(`Verified employee ${employeeId} is linked to Firebase Auth. DRY RUN ONLY.`);
    console.log('After offline identity verification, run again with --apply and NEW_EMPLOYEE_PASSWORD.');
  } else {
    await admin.auth().updateUser(user.uid, {password: newPassword});
    console.log(`Password reset for employee ${employeeId}. Share the new password privately and request immediate change.`);
  }
} catch (error) {
  console.error('Account recovery failed:', error.message);
  process.exitCode = 1;
}

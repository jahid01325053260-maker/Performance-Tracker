/**
 * Spark Free / legacy Firebase Auth UID repair (trusted operator only).
 * DRY RUN by default. APPLY=1 BACKUP_CONFIRMED=1 required for writes.
 * Set GOOGLE_APPLICATION_CREDENTIALS to a private, local service account JSON;
 * never upload credentials to Github, an APK, or this ZIP.
 * Optional TARGET_EMPLOYEE_ID=<12 digits> to repair one ID at a time.
 */
const admin = require('firebase-admin');
const crypto = require('node:crypto');
const projectId = process.env.FIREBASE_PROJECT_ID;
const target = (process.env.TARGET_EMPLOYEE_ID || '').trim();
if (!projectId || (target && !/^\d{12}$/.test(target))) {
  throw new Error('Provide FIREBASE_PROJECT_ID; TARGET_EMPLOYEE_ID must be 12 digits.');
}
admin.initializeApp({credential: admin.credential.applicationDefault(), projectId});
const db = admin.firestore(), auth = admin.auth();
const apply = process.env.APPLY === '1' && process.env.BACKUP_CONFIRMED === '1';
const sha = id => crypto.createHash('sha256').update(id).digest('hex');
const alias = id => `pt-${sha(id).slice(0,40)}@performance-tracker.invalid`;
const getByUid = async uid => {
  try { return await auth.getUser(uid); }
  catch(e) { if (e.code === 'auth/user-not-found') return null; throw e; }
};
const getByEmail = async email => {
  try { return await auth.getUserByEmail(email); }
  catch(e) { if (e.code === 'auth/user-not-found') return null; throw e; }
};
async function run() {
  console.log(apply ? 'APPLY after verified backup' : 'DRY RUN; no writes');
  const employees = target
    ? [await db.collection('employees').doc(target).get()]
    : (await db.collection('employees').get()).docs;
  let repaired = 0, review = 0;
  for (const doc of employees) {
    if (!doc.exists) { console.log('Employee document not found'); review++; continue; }
    const id = doc.id, employee = doc.data();
    if (!/^\d{12}$/.test(id)) { console.log(`Invalid ID: ${id}`); review++; continue; }
    const idxRef = db.collection('login_index').doc(sha(id));
    const idxSnap = await idxRef.get();
    const idx = idxSnap.data() || {};
    // Only trust Auth UIDs and sign-in emails, NEVER name/branch similarity.
    const candidates = new Map();
    const add = user => { if(user) candidates.set(user.uid, user); };
    if (employee.authUid) add(await getByUid(employee.authUid));
    if (idx.authUid) add(await getByUid(idx.authUid));
    if (typeof idx.email === 'string' && idx.email.includes('@')) {
      add(await getByEmail(idx.email.trim().toLowerCase()));
    }
    add(await getByEmail(alias(id)));
    const identities = await db.collection('auth_users').where('employeeId','==',id).get();
    for (const identity of identities.docs) add(await getByUid(identity.id));
    if (candidates.size !== 1) {
      console.log(`${id}: ${candidates.size} possible Auth accounts; MANUAL REVIEW`);
      review++; continue;
    }
    const user = Array.from(candidates.values())[0];
    if ((employee.authUid && employee.authUid !== user.uid) ||
        (idx.authUid && idx.authUid !== user.uid)) {
      console.log(`${id}: conflicting existing UID; MANUAL REVIEW`);
      review++; continue;
    }
    const otherEmployee = await db.collection('employees').where('authUid','==',user.uid).get();
    if (otherEmployee.docs.some(d => d.id !== id)) {
      console.log(`${id}: UID already linked to another employee; MANUAL REVIEW`);
      review++; continue;
    }
    const identityRef = db.collection('auth_users').doc(user.uid);
    const identity = (await identityRef.get()).data();
    if (identity && identity.employeeId !== id) {
      console.log(`${id}: auth_users UID belongs to ${identity.employeeId}; MANUAL REVIEW`);
      review++; continue;
    }
    const indexNeedsRepair = idxSnap.exists && (idx.authUid !== user.uid || idx.email !== user.email);
    if (employee.authUid === user.uid && identity && identity.employeeId === id && !indexNeedsRepair) {
      console.log(`${id}: already linked`); continue;
    }
    console.log(`${id}: verified UID ${user.uid}; ${apply ? 'repairing' : 'would repair'}`);
    if (apply) {
      const batch = db.batch();
      batch.set(doc.ref,{authUid:user.uid},{merge:true});
      batch.set(identityRef, {employeeId:id,
        role:employee.role || 'USER', status:employee.status || 'Approved'}, {merge:true});
      // Existing Android login_index must point to the same verified Auth email
      // or ID/password login may still fail after fixing the UID. Do not
      // create public index docs for modern alias-only registrations.
      if (idxSnap.exists) {
        batch.set(idxRef, {employeeId:id, authUid:user.uid, email:user.email}, {merge:true});
      }
      await batch.commit(); repaired++;
    }
  }
  console.log(JSON.stringify({repaired, manualReview:review, applied:apply}));
}
run().catch(e => { console.error(e); process.exitCode=1; });

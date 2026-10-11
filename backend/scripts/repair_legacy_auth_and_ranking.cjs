/**
 * Local Admin-SDK migration. NO client service account credentials.
 * Default is dry-run. APPLY=1 required for writes; BACKUP_CONFIRMED=1 required.
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS points to private JSON outside repo.
 * Usage: cd backend && node scripts/repair_legacy_auth_and_ranking.cjs
 *         APPLY=1 BACKUP_CONFIRMED=1 node scripts/repair_legacy_auth_and_ranking.cjs
 * Never check the service account into GitHub; run only on a trusted PC.
 */
const admin = require('firebase-admin');
const crypto = require('node:crypto');
admin.initializeApp({credential:admin.credential.applicationDefault()});
const db=admin.firestore();const auth=admin.auth();
const apply=process.env.APPLY==='1' && process.env.BACKUP_CONFIRMED==='1';
const idHash=id=>crypto.createHash('sha256').update(id).digest('hex');
const alias=id=>`pt-${idHash(id).slice(0,40)}@performance-tracker.invalid`;
const normalizedRole=raw=> {
  const r=(raw||'').trim().toLowerCase();
  return ({'user':'USER','sales manager':'Sales Manager','agm':'AGM',
    'dgm':'DGM','admin':'ADMIN'})[r] || null;
};
async function main(){
  console.log(apply?'APPLY enabled after explicit backup confirmation':'DRY RUN — no writes');
  const docs=await db.collection('employees').get();
  let counts=0,authLinked=0,needsManual=0;
  for(const doc of docs.docs){
    const id=doc.id; const e=doc.data();
    if(!/^\d{12}$/.test(id)) {console.log('Skip invalid Employee ID');continue;}
    const role=normalizedRole(e.role);if(!role){needsManual++; console.log(`${id}: role needs manual review`);continue;}
    const status=(e.status||'').trim().toLowerCase()==='approved'?'Approved':
      (e.status||'').trim()===''?'Approved': e.status;
    const idxRef=db.collection('login_index').doc(idHash(id));
    const idx=(await idxRef.get()).data()||{};
    // Honor the original Android login_index email as the authoritative sign-in.
    const email=(idx.email||alias(id)).trim().toLowerCase();
    let user=null;
    try {user=idx.authUid?await auth.getUser(idx.authUid):await auth.getUserByEmail(email);}
    catch(err){if(err.code!=='auth/user-not-found')throw err;}
    if(!user){
      // Keep existing passwords only where they are already stored by legacy code;
      // DO NOT export, print, collect, or copy them outside the local migration.
      if(typeof e.password!=='string'||e.password.length<6){
        console.log(`${id}: no Auth user, no migration credential — admin-verified password reset required`);
        needsManual++;continue;
      }
      console.log(`${id}: legacy Firebase Auth user needs migration`);
      if(apply) user=await auth.createUser({email,password:e.password});
    }
    if(user){
      if(e.authUid && e.authUid!==user.uid){
        console.log(`${id}: conflicting UID, manual review required`);needsManual++;continue;
      }
      const other=(await db.collection('auth_users').doc(user.uid).get()).data();
      if(other && other.employeeId!==id){console.log(`${id}: UID belongs to another ID, STOP`);needsManual++;continue;}
      console.log(`${id}: link Firebase Authentication / role ${role}`);
      if(apply){
        const batch=db.batch();
        batch.set(doc.ref,{authUid:user.uid,role,status,password:admin.firestore.FieldValue.delete()}, {merge:true});
        batch.set(db.collection('auth_users').doc(user.uid),{employeeId:id,role,status},{merge:true});
        batch.set(idxRef,{employeeId:id,authUid:user.uid,email,updatedAt:Date.now()},{merge:true});
        await batch.commit();authLinked++;
      }
    }
    // Aggregate actual 906 records, unique per employee/reportingPeriod/account.
    const rows=await db.collection('performance').where('employeeId','==',id).get();
    const keys=new Set();
    for(const r of rows.docs){const v=r.data();const key=String(v.accountNo||'').replace(/\D/g,'');
      if(v.status==='deleted'||v.status==='rejected'||v.limit==='NIL'||
        !/^\d{4}906\d{6}$/.test(key))continue;
      const period=String(v.reportingPeriod||'');
      if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(period)){console.log(`${id}: unmigrated period for a record; review`);continue;}
      keys.add(`${period}|${key}`);
    }
    console.log(`${id}: ${keys.size} verified 906 cards across all periods`);
    if(apply) {
      const ref=db.collection('leaderboard').doc(id);
      await ref.set({employeeId:id,cards:keys.size,updatedAt:admin.firestore.FieldValue.serverTimestamp()}, {merge:true});
      counts++;
    }
  }
  console.log(JSON.stringify({employees:docs.size,authLinked,rankingsUpdated:counts,needsManual,applied:apply}));
  if(!apply) console.log('To apply: BACK UP Firestore/Auth first, then set APPLY=1 BACKUP_CONFIRMED=1 on a trusted machine.');
}
main().catch(e=>{console.error(e.message);process.exitCode=1});

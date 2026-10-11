// ONE-TIME TRUSTED OPERATOR SCRIPT. Never call it from Flutter or from an HTTP route.
import admin from 'firebase-admin';
import {createHash} from 'node:crypto';
const id=process.env.ADMIN_EMPLOYEE_ID||'';
const name=process.env.ADMIN_NAME||'';
const password=process.env.ADMIN_PASSWORD||'';
const projectId=process.env.FIREBASE_PROJECT_ID||'';
if(!/^\d{12}$/.test(id)||name.length<2||password.length<12||!projectId){
  console.error('Set FIREBASE_PROJECT_ID, ADMIN_EMPLOYEE_ID (12 digits), ADMIN_NAME and ADMIN_PASSWORD (12+ chars)');
  process.exit(1);
}
admin.initializeApp({credential:admin.credential.applicationDefault(),projectId});
const db=admin.firestore();const hash=createHash('sha256').update(id).digest('hex');
const email=`pt-${hash.slice(0,40)}@performance-tracker.invalid`;
const existing=await db.collection('employees').doc(id).get();
if(existing.exists){console.error('Refusing to modify an existing employee');process.exit(1);}
const auth=admin.auth();let user;
try{
  user=await auth.createUser({email,password,displayName:name});
  const batch=db.batch();
  batch.create(db.collection('employees').doc(id),{
    employeeId:id,name,authUid:user.uid,email:process.env.ADMIN_RECOVERY_EMAIL||'',
    branch:process.env.ADMIN_BRANCH||'',zone:process.env.ADMIN_ZONE||'',
    mobile:'',officialNumber:'',salesManager:'',managerId:'',department:'',profileImage:'',
    role:'ADMIN',status:'Approved',monthlyTarget:0,yearlyTarget:0,createdAt:Date.now(),schemaVersion:2,
  });
  batch.create(db.collection('auth_users').doc(user.uid),{employeeId:id,role:'ADMIN',status:'Approved'});
  batch.create(db.collection('login_index').doc(hash),{employeeId:id,email,authUid:user.uid});
  await batch.commit();
  console.log(`ADMIN provisioned for employee ID ${id}. Save credentials in your company secrets manager.`);
}catch(e){if(user)await auth.deleteUser(user.uid).catch(()=>{});console.error('Bootstrap failed:',e.message);process.exit(1);}

import express from 'express';
import multer from 'multer';
import pdfParse from 'pdf-parse';
import admin from 'firebase-admin';
import {randomUUID} from 'node:crypto';
import {sha256, normalize,upper,account,canonicalAccount,employeePattern,periodPattern,monthNames,recordPeriod,countCards,aliasFor} from './logic.js';

// Firebase Cloud Functions automatically provides project credentials.
if (admin.apps.length === 0) admin.initializeApp();
const db=admin.firestore(), auth=admin.auth();
const app=express();app.disable('x-powered-by');app.use(express.json({limit:'160kb'}));
app.use((req,res,next)=>{res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');next();});
const asyncRoute=fn=>(req,res,next)=>Promise.resolve(fn(req,res,next)).catch(next);
const reject=(status,message)=>Object.assign(new Error(message),{status});
const assert=(ok,status,message)=>{if(!ok)throw reject(status,message);};
const idOf=req=>req.identity.employeeId;
const isAdmin=req=>req.identity.role==='ADMIN';
const currentRole=e=>String(e.role||'USER').trim();
const safeFields=e=>{
  const copy={...e};delete copy.password;delete copy.authEmail;delete copy.authUid;
  if(copy.profileImage?.length>275000)delete copy.profileImage;
  return copy;
};
const audit=async(req,action,details={})=>db.collection('audit_logs').add({actorUid:req.uid,actorEmployeeId:idOf(req),action,details,at:admin.firestore.FieldValue.serverTimestamp()});

// Basic per-IP protection is an extra layer. Configure distributed gateway limits in production.
const hits=new Map();
function rateLimit(req,res,next){
  const key=`${req.ip}:${req.path}`;const now=Date.now();
  let entry=hits.get(key);if(!entry||now-entry.start>60000)entry={start:now,count:0};
  entry.count++;hits.set(key,entry);
  if(hits.size>15000)hits.clear();
  if(entry.count>12)return res.status(429).json({error:'Too many requests. Try again later.'});
  next();
}
app.get('/health',(req,res)=>res.json({status:'ok'}));

app.post('/v1/auth/login',rateLimit,asyncRoute(async(req,res)=>{
  const employeeId=normalize(req.body.employeeId),password=req.body.password;
  assert(employeePattern.test(employeeId)&&typeof password==='string'&&password.length>0,400,'Invalid login');
  const index=await db.collection('login_index').doc(sha256(employeeId)).get();
  // Legacy index entries use .email. Only the backend accesses these sensitive indexes.
  const email=index.exists?index.get('email'):aliasFor(employeeId);
  assert(typeof email==='string'&&email.includes('@'),401,'Invalid employee ID or password');
  // The Google API key is a public client configuration value supplied by Firebase SDK.
  // Firebase Admin verifies the resulting token against THIS project's identity.
  const apiKey=String(req.body.firebaseApiKey||'');
  assert(/^AIza[0-9A-Za-z_-]{30,80}$/.test(apiKey),400,'Firebase configuration missing');
  const response=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
    {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password,returnSecureToken:true})});
  const body=await response.json();
  assert(response.ok&&body.idToken,401,'Invalid employee ID or password');
  const decoded=await auth.verifyIdToken(body.idToken);
  const identity=await db.collection('auth_users').doc(decoded.uid).get();
  const profile=await db.collection('employees').doc(employeeId).get();
  assert(identity.exists&&identity.get('employeeId')===employeeId&&profile.exists&&profile.get('authUid')===decoded.uid,403,'Account requires administrator verification');
  assert(profile.get('status')==='Approved'&&identity.get('status')==='Approved',403,'Account is not approved or has been disabled');
  // Flutter signs in with the Firebase SDK so the session is persisted and refreshed.
  const customToken=await auth.createCustomToken(decoded.uid);
  res.json({customToken});
}));

// Registration creates a Firebase Auth user through trusted infrastructure only.
async function createAccount(input,role='USER',status='Pending'){
  const employeeId=normalize(input.employeeId), name=normalize(input.name),password=input.password;
  assert(employeePattern.test(employeeId),400,'Employee ID must contain exactly 12 digits');
  assert(name.length>=2&&name.length<=120,400,'Invalid full name');
  assert(typeof password==='string'&&password.length>=8&&password.length<=128,400,'Password must be 8–128 characters');
  const email=normalize(input.email||'').toLowerCase();
  assert(!email||/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email),400,'Invalid recovery email');
  const profileRef=db.collection('employees').doc(employeeId);
  assert(!(await profileRef.get()).exists,409,'Employee ID already registered');
  const authEmail=aliasFor(employeeId); // Recovery email is kept separately.
  const created=await auth.createUser({email:authEmail,password,displayName:name,disabled:false});
  try{
    const batch=db.batch();const uid=created.uid;
    batch.create(profileRef,{
      employeeId,name,email,branch:upper(input.branch),zone:upper(input.zone),salesManager:normalize(input.salesManager),
      mobile:normalize(input.mobile),officialNumber:normalize(input.officialNumber),department:normalize(input.department),
      managerId:normalize(input.managerId),role,status,monthlyTarget:0,yearlyTarget:0,profileImage:'',authUid:uid,
      createdAt:Date.now(),schemaVersion:2,
    });
    batch.create(db.collection('login_index').doc(sha256(employeeId)),{employeeId,email:authEmail,authUid:uid});
    batch.create(db.collection('auth_users').doc(uid),{employeeId,role,status});
    await batch.commit();
    return employeeId;
  }catch(e){await auth.deleteUser(created.uid).catch(()=>{});throw e;}
}
app.post('/v1/registrations',rateLimit,asyncRoute(async(req,res)=>{
  // No client-supplied roles or approval states accepted.
  await createAccount(req.body,'USER','Pending');res.status(201).json({message:'Awaiting ADMIN approval'});
}));

async function authenticated(req,res,next){
  try{
    const token=/^Bearer (\S+)$/i.exec(req.get('authorization')||'')?.[1];assert(token,401,'Sign in required');
    const decoded=await auth.verifyIdToken(token,true);
    const identity=await db.collection('auth_users').doc(decoded.uid).get();
    assert(identity.exists,403,'Unknown identity');
    const employeeId=identity.get('employeeId');assert(employeePattern.test(employeeId),403,'Invalid identity');
    const profile=await db.collection('employees').doc(employeeId).get();
    assert(profile.exists&&profile.get('authUid')===decoded.uid,403,'Identity mismatch');
    assert(profile.get('status')==='Approved'&&identity.get('status')==='Approved',403,'Account is not approved');
    assert(profile.get('role')===identity.get('role'),403,'Role out of sync');
    req.uid=decoded.uid;req.identity={...profile.data(),employeeId};next();
  }catch(e){next(e);}
}
app.use('/v1',authenticated);
app.get('/v1/me',(req,res)=>res.json(safeFields(req.identity)));

const roster=async(req)=>{
  const employees=(await db.collection('employees').where('status','==','Approved').limit(2500).get()).docs.map(d=>d.data());
  if(isAdmin(req))return employees;
  if(req.identity.role==='USER')return employees; // directory data, not report access
  if(req.identity.role==='Sales Manager')return employees.filter(e=>e.employeeId===idOf(req)||e.managerId===idOf(req)||
    (!e.managerId&&upper(e.salesManager)===upper(req.identity.name)));
  const zones=Array.isArray(req.identity.authorizedZones)?req.identity.authorizedZones.map(upper):[];
  return employees.filter(e=>e.employeeId===idOf(req)||zones.includes(upper(e.zone)));
};
const permittedReportIds=async(req)=>{
  if(req.identity.role==='USER')return new Set([idOf(req)]);
  const visible=await roster(req);
  return new Set(visible.filter(e=>e.role==='USER').map(e=>e.employeeId));
};
function redactEmployee(e,req){
  const value=safeFields(e);
  if(!isAdmin(req)&&idOf(req)!==e.employeeId){delete value.email;delete value.mobile;delete value.officialNumber;}
  return value;
}
app.get('/v1/employees',asyncRoute(async(req,res)=>{
  const visible=await roster(req),q=upper(req.query.q||''),role=req.query.role||'All';
  const filtered=visible.filter(e=>(role==='All'||e.role?.toLowerCase()===String(role).toLowerCase())&&
    [e.employeeId,e.name,e.branch,e.zone,e.salesManager,e.department].some(s=>upper(s).includes(q))).slice(0,500);
  res.json(filtered.map(e=>redactEmployee(e,req)));
}));
app.get('/v1/employees/:id',asyncRoute(async(req,res)=>{
  assert((await roster(req)).some(e=>e.employeeId===req.params.id),403,'Access denied');
  const doc=await db.collection('employees').doc(req.params.id).get();assert(doc.exists,404,'Employee not found');
  res.json(redactEmployee(doc.data(),req));
}));
app.patch('/v1/employees/:id/profile',asyncRoute(async(req,res)=>{
  const id=req.params.id;assert(isAdmin(req)||id===idOf(req),403,'Access denied');
  const allowed=isAdmin(req)?['name','mobile','email','officialNumber','branch','zone','department','profileImage']:['name','mobile','email','officialNumber','profileImage'];
  const updates={};for(const key of allowed)if(Object.hasOwn(req.body,key)){
    if(key==='profileImage'){
      const image=req.body[key];
      assert(typeof image==='string'&&image.length<=260000&&/^[A-Za-z0-9+/]*={0,2}$/.test(image),400,'Invalid compressed profile photo');
      updates[key]=image;continue;
    }
    assert(typeof req.body[key]==='string'&&req.body[key].length<200,400,'Invalid field');
    updates[key]=['branch','zone'].includes(key)?upper(req.body[key]):normalize(req.body[key]);
  }
  assert(Object.keys(updates).length>0,400,'No permitted fields');
  await db.collection('employees').doc(id).update({...updates,updatedAt:Date.now()});
  await audit(req,'profile.update',{employeeId:id,fields:Object.keys(updates)});res.json({ok:true});
}));

async function fetchReports(req, employeeId=null, period=null){
  const allowed=await permittedReportIds(req);
  if(employeeId){assert(allowed.has(employeeId),403,'Not authorized to view reports');}
  // Scoped query: only allowed employee IDs. Firestore `in` queries support up to 30 IDs.
  const ids=employeeId?[employeeId]:[...allowed];
  const results=[];
  for(let i=0;i<ids.length;i+=30){const batch=ids.slice(i,i+30);if(!batch.length)continue;
    const query=batch.length===1?db.collection('performance').where('employeeId','==',batch[0]):db.collection('performance').where('employeeId','in',batch);
    const snap=await query.limit(3000).get();
    for(const doc of snap.docs){const row={id:doc.id,...doc.data()};if(!period||recordPeriod(row)===period)results.push(row);}
  }
  return results;
}
app.get('/v1/performance',asyncRoute(async(req,res)=>{
  const period=req.query.period;
  if(period)assert(periodPattern.test(period),400,'Invalid period');
  res.json(await fetchReports(req,req.query.employeeId||null,period||null));
}));
function validateRows(rows){
  assert(Array.isArray(rows)&&rows.length<=50,400,'Up to 50 entries per batch');
  return rows.map(r=>{
    const applicantName=normalize(r.applicantName),limit=normalize(r.limit);
    assert(applicantName.length>0&&applicantName.length<=160&&upper(applicantName)!=='REVIEW REQUIRED',400,'Applicant name required');
    assert(limit.length>0&&limit.length<=80&&upper(limit)!=='NIL'&&upper(limit)!=='REVIEW REQUIRED',400,'Valid reviewed limit required');
    return {applicantName,accountNo:canonicalAccount(r.accountNo),limit};
  });
}
app.post('/v1/performance/batch',asyncRoute(async(req,res)=>{
  assert(req.identity.role==='USER'||isAdmin(req),403,'Only officers may submit');
  const period=req.body.reportingPeriod;assert(periodPattern.test(period),400,'Invalid reporting period');
  const nil=req.body.nil===true;
  const rows=nil?[]:validateRows(req.body.rows);
  assert(nil||rows.length>0,400,'At least one card is required');
  assert(!nil||(!Array.isArray(req.body.rows)||req.body.rows.length===0),400,'NIL and cards cannot be combined');
  const owner=idOf(req),emp=req.identity;
  const base={employeeId:owner,employeeName:emp.name,branch:emp.branch,zone:emp.zone,salesManager:emp.salesManager,
    reportingPeriod:period,year:Number(period.slice(0,4)),month:monthNames[Number(period.slice(5))-1],updatedAt:Date.now(),status:'confirmed'};
  const nilRef=db.collection('performance').doc(sha256(`${owner}|${period}|NIL`));
  // Stable document IDs make batch retries idempotent. Transaction supersedes NIL.
  const items=rows.map(row=>({ref:db.collection('performance').doc(sha256(`${owner}|${period}|${account(row.accountNo)}`)),row}));
  assert(new Set(items.map(x=>x.ref.id)).size===items.length,400,'Duplicate account in submitted rows');
  await db.runTransaction(async tx=>{
    const nilDoc=await tx.get(nilRef);
    const existing=await Promise.all(items.map(x=>tx.get(x.ref)));
    if(nil){
      // Protect a valid existing new-schema submission from a later NIL overwrite.
      const confirmed=await tx.get(db.collection('performance').where('employeeId','==',owner).where('reportingPeriod','==',period).limit(50));
      assert(!confirmed.docs.some(d=>d.id!==nilRef.id&&d.get('status')!=='deleted'),409,'Existing real submissions prevent NIL');
      tx.set(nilRef,{...base,applicantName:'NIL',accountNo:'N/A',limit:'NIL',timestamp:Date.now()},{merge:true});
    }else{
      if(nilDoc.exists)tx.delete(nilRef);
      for(let i=0;i<items.length;i++){
        const {ref,row}=items[i];
        tx.set(ref,{...base,...row,timestamp:existing[i].exists?existing[i].get('timestamp'):Date.now(),source:'manual'},{merge:true});
      }
    }
  });
  await audit(req,'performance.submit',{period,count:rows.length,nil});res.json({ok:true,count:rows.length});
}));
async function editableRecord(req,id){
  const ref=db.collection('performance').doc(id),doc=await ref.get();
  assert(doc.exists,404,'Record not found');
  const data=doc.data();
  assert(isAdmin(req)||data.employeeId===idOf(req),403,'You cannot change this report');
  return {ref,data};
}
app.patch('/v1/performance/:id',asyncRoute(async(req,res)=>{
  const {ref,data}=await editableRecord(req,req.params.id);
  const updates={};if(Object.hasOwn(req.body,'applicantName')){
    updates.applicantName=normalize(req.body.applicantName);assert(updates.applicantName.length>0,400,'Name required');}
  if(Object.hasOwn(req.body,'limit')){updates.limit=normalize(req.body.limit);assert(updates.limit.length>0,400,'Limit required');}
  if(Object.hasOwn(req.body,'accountNo')){
    // Avoid moving into an ID clash in another transaction; use delete+recreate through resubmission.
    const next=canonicalAccount(req.body.accountNo);
    assert(account(next)===account(data.accountNo),409,'Changing account number requires delete and new submission');
    updates.accountNo=next;
  }
  assert(Object.keys(updates).length>0,400,'Nothing to update');
  await ref.update({...updates,updatedAt:Date.now()});await audit(req,'performance.edit',{id:ref.id});res.json({ok:true});
}));
app.delete('/v1/performance/:id',asyncRoute(async(req,res)=>{
  const {ref}=await editableRecord(req,req.params.id);await ref.update({status:'deleted',updatedAt:Date.now()});
  await audit(req,'performance.delete',{id:ref.id});res.json({ok:true});
}));
app.get('/v1/targets',asyncRoute(async(req,res)=>{
  const allowed=await permittedReportIds(req);const ids=[...allowed];const entries=[];
  for(let i=0;i<ids.length;i+=30){const batch=ids.slice(i,i+30);if(!batch.length)continue;
    const snap=await db.collection('targets').where('employeeId','in',batch).limit(2500).get();for(const d of snap.docs){
      const t=d.data();const period=t.reportingPeriod||recordPeriod({month:t.month,year:t.year});if(!req.query.period||period===req.query.period)entries.push({...t,reportingPeriod:period});
    }
  }
  res.json(entries);
}));
function requireAdmin(req,res,next){if(!isAdmin(req))return next(reject(403,'Admin access required'));next();}
app.put('/v1/admin/targets/:id/:year/:month',requireAdmin,asyncRoute(async(req,res)=>{
  const {id,year,month}=req.params,period=`${year}-${month}`;
  assert(employeePattern.test(id)&&periodPattern.test(period),400,'Invalid employee or period');
  const t=Number(req.body.targetCards),annual=Number(req.body.yearlyTargetCards);
  assert(Number.isSafeInteger(t)&&t>=0&&Number.isSafeInteger(annual)&&annual>=0,400,'Invalid target');
  const employee=await db.collection('employees').doc(id).get();assert(employee.exists&&employee.get('role')==='USER',404,'Officer not found');
  await db.collection('targets').doc(`${id}_${year}_${month}`).set({employeeId:id,employeeName:employee.get('name'),year:Number(year),month:monthNames[Number(month)-1],
    reportingPeriod:period,targetCards:t,yearlyTargetCards:annual,updatedBy:idOf(req),updatedAt:Date.now()});
  await audit(req,'target.update',{employeeId:id,period,targetCards:t});res.json({ok:true});
}));
app.get('/v1/admin/approvals',requireAdmin,asyncRoute(async(req,res)=>{
  const pending=await db.collection('employees').where('status','==','Pending').limit(200).get();
  res.json(pending.docs.map(d=>safeFields(d.data())));
}));
app.post('/v1/admin/approvals/:id/:decision',requireAdmin,asyncRoute(async(req,res)=>{
  const id=req.params.id;assert(['approve','reject'].includes(req.params.decision),400,'Invalid decision');
  const ref=db.collection('employees').doc(id),doc=await ref.get();assert(doc.exists&&doc.get('status')==='Pending',409,'Not pending');
  const status=req.params.decision==='approve'?'Approved':'Rejected';
  const batch=db.batch();batch.update(ref,{status});batch.update(db.collection('auth_users').doc(doc.get('authUid')),{status});await batch.commit();
  await audit(req,'approval.update',{employeeId:id,status});res.json({ok:true});
}));
app.post('/v1/admin/employees/management',requireAdmin,asyncRoute(async(req,res)=>{
  assert(['Sales Manager','AGM','DGM'].includes(req.body.role),400,'Invalid management role');
  const id=await createAccount(req.body,req.body.role,'Approved');
  await audit(req,'management.create',{employeeId:id,role:req.body.role});res.status(201).json({employeeId:id});
}));
app.post('/v1/audit/export',asyncRoute(async(req,res)=>{
  await audit(req,'export.client',{format:String(req.body.type||'').slice(0,30)});res.json({ok:true});
}));

const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:10*1024*1024,files:1}});
app.post('/v1/import/pdf',upload.single('file'),asyncRoute(async(req,res)=>{
  assert(req.identity.role==='USER',403,'Officer account required');
  assert(req.file?.buffer?.subarray(0,4).toString()==='%PDF',400,'PDF file required');
  let result;try {result=await pdfParse(req.file.buffer);}catch{throw reject(422,'Unreadable or protected PDF');}
  const lines=result.text.split(/\r?\n/).map(normalize).filter(Boolean);
  // Conservative extraction only; review UI must confirm applicant/period and amounts.
  const rows=[],seen=new Set();const pattern=/\b(\d{4})[-\s]?(906)[-\s]?(\d{6})\b/g;
  for(let i=0;i<lines.length;i++){
    const line=lines[i],date=line.match(/\b(\d{1,2})[-/](\d{1,2})[-/](20\d{2})\b/);
    for(const match of line.matchAll(pattern)){
      const acc=`${match[1]}-906-${match[3]}`;if(seen.has(acc))continue;seen.add(acc);
      const period=date?`${date[3]}-${String(Number(date[2])).padStart(2,'0')}`:null;
      const title=line.replace(match[0],'').replace(/\d{1,2}[-/]\d{1,2}[-/]20\d{2}/g,'').trim();
      rows.push({accountNo:acc,applicantName:title.substring(0,120)||'REVIEW REQUIRED',limit:'REVIEW REQUIRED',reportingPeriod:period,reviewRequired:true});
    }
  }
  res.json({rows:rows.slice(0,250),warning:'Verify title, limit and period. This extractor does not infer ambiguous values.'});
}));

app.use((err,req,res,next)=>{
  const status=err.status||((err.code==='LIMIT_FILE_SIZE')?413:500);
  if(status>=500)console.error(err);
  res.status(status).json({error:status>=500?'Internal server error':err.message});
});
export {app};

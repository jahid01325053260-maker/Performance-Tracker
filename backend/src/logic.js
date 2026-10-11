import {createHash} from 'node:crypto';
export const sha256 = s => createHash('sha256').update(s).digest('hex');
export const normalize = s => String(s??'').trim().replace(/\s+/g,' ');
export const upper = s => normalize(s).toUpperCase();
export const account = s => String(s??'').replace(/[^0-9]/g,'');
export const employeePattern = /^\d{12}$/;
export const periodPattern = /^\d{4}-(0[1-9]|1[0-2])$/;
export const accountPattern = /^\d{4}906\d{6}$/;
export const monthNames=['January','February','March','April','May','June','July','August','September','October','November','December'];
export function recordPeriod(row){
  if(periodPattern.test(row.reportingPeriod??''))return row.reportingPeriod;
  let monthIndex=monthNames.findIndex(x=>x.toLowerCase()===String(row.month??'').toLowerCase());
  const time=Number(row.timestamp);
  const date=Number.isFinite(time)&&time>0?new Date(time):null;
  const year=Number(row.year)||date?.getUTCFullYear();
  const month=monthIndex>=0?monthIndex+1:date?.getUTCMonth()+1;
  return year&&month?`${year}-${String(month).padStart(2,'0')}`:null;
}
export function isNil(r){return upper(r.limit)==='NIL'||upper(r.accountNo)==='N/A';}
export function countCards(records,{employeeId=null,period=null}={}){
  const seen=new Set();
  for(const r of records){
    if(r.status==='deleted'||r.status==='rejected'||isNil(r))continue;
    if(employeeId!=null&&r.employeeId!==employeeId)continue;
    const p=recordPeriod(r);if(!p||(period!=null&&p!==period))continue;
    const a=account(r.accountNo);if(!a)continue;
    seen.add(`${r.employeeId}|${p}|${a}`);
  }
  return seen.size;
}
export function achievement(achieved,target){
  const percent=target>0?achieved*100/target:null;
  return {achieved,target,percentage:percent,below50:target>0&&percent<50,
    needsFor50:target>0&&percent<50?Math.max(0,Math.ceil(target/2)-achieved):0,
    shortfall:Math.max(0,target-achieved)};
}
export function canonicalAccount(input){
  const clean=account(input);
  if(!accountPattern.test(clean))throw new Error('Only valid 906 account numbers are accepted');
  return `${clean.slice(0,4)}-${clean.slice(4,7)}-${clean.slice(7)}`;
}
export function aliasFor(id){return `pt-${sha256(id).slice(0,40)}@performance-tracker.invalid`;}

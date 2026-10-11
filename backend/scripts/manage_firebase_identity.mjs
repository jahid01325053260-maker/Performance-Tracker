#!/usr/bin/env node
/**
 * Trusted ADMIN DESKTOP ONLY; NEVER embed firebase-admin credentials in Flutter.
 * Examples:
 *  node backend/scripts/manage_firebase_identity.mjs --action=reset --id=123456789012 --confirm=123456789012 --project=your-project
 *  node backend/scripts/manage_firebase_identity.mjs --action=delete --id=123456789012 --confirm=123456789012 --project=your-project
 * Requires Google Application Default Credentials with Firebase Auth admin IAM.
 */
import process from 'node:process';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { createHash } = require('node:crypto');
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

const flags = Object.fromEntries(process.argv.slice(2).filter(a => a.startsWith('--')).map(a => {
  const [key, ...value] = a.substring(2).split('=');
  return [key, value.join('=')];
}));
const { action, id, confirm, project } = flags;
if (!['delete', 'reset'].includes(action) || !/^\d{12}$/.test(id || '') || confirm !== id || !project) {
  process.stderr.write('Usage: node backend/scripts/manage_firebase_identity.mjs --action=delete|reset --id=12-digit-ID --confirm=same-ID --project=FIREBASE-PROJECT-ID\n');
  process.exit(2);
}

function readSecret() {
  if (!process.stdin.isTTY || !process.stdin.setRawMode) throw new Error('Run from an interactive desktop terminal. Password input cannot be redirected.');
  return new Promise((resolve, reject) => {
    process.stdout.write('New temporary password (hidden input, 8+ characters): ');
    let value = '';
    process.stdin.setRawMode(true);
    process.stdin.resume();
    const listener = buffer => {
      for (const char of buffer.toString('utf8')) {
        if (char === '\r' || char === '\n') {
          process.stdin.setRawMode(false);
          process.stdin.pause();
          process.stdin.removeListener('data', listener);
          process.stdout.write('\n');
          resolve(value);
          return;
        }
        if (char === '\u0003') {
          process.stdin.setRawMode(false);
          process.stdin.pause();
          process.stdin.removeListener('data', listener);
          reject(new Error('Cancelled by administrator'));
          return;
        }
        if (char === '\u007f' || char === '\b') { value = value.slice(0,-1); }
        else if (char >= ' ' && char !== '\u007f') { value += char; }
      }
    };
    process.stdin.on('data', listener);
  });
}

async function run() {
  initializeApp({ credential: applicationDefault(), projectId: project });
  const db = getFirestore();
  const users = getAuth();
  const employeeRef = db.collection('employees').doc(id);
  const snapshot = await employeeRef.get();
  if (!snapshot.exists) throw new Error('No employee profile; refusing to guess Auth UID.');
  const details = snapshot.data();
  const uid = String(details.authUid || '');
  if (!uid) throw new Error('Employee has no authUid; run identity mapping repair first.');
  const identityRef = db.collection('auth_users').doc(uid);
  const identity = await identityRef.get();
  if (!identity.exists || String(identity.data().employeeId || '') !== id) {
    throw new Error('Identity mismatch; refusing to modify any Firebase account.');
  }
  if (details.role === 'ADMIN' && flags['allow-admin-role'] !== 'yes') {
    throw new Error('Refusing to modify ADMIN. Explicitly pass --allow-admin-role=yes after secondary verification.');
  }
  if (action === 'reset') {
    const password = await readSecret();
    if (password.length < 8) throw new Error('Temporary password must have at least 8 characters.');
    await users.updateUser(uid, { password });
    process.stdout.write(`Firebase Auth password reset for employee ${id}. Share the temporary password privately; require immediate change.\n`);
    return;
  }
  if (details.status !== 'Disabled' || identity.data().status !== 'Disabled') {
    throw new Error('Account must first be disabled in app before permanent deletion.');
  }
  const requestRef = db.collection('identity_deletion_requests').doc(id);
  const req = await requestRef.get();
  if (!req.exists || req.data().status !== 'pending' || req.data().authUid !== uid) {
    throw new Error('No matching admin deletion request; refusing to delete identity.');
  }
  const hashed = createHash('sha256').update(id).digest('hex');
  const index = db.collection('login_index').doc(hashed);
  const indexData = await index.get();
  if (indexData.exists && indexData.data().authUid && indexData.data().authUid !== uid) {
    throw new Error('Login index points to different UID; refusing to delete.');
  }
  // Firebase Auth deleted before Firestore to ensure credentials cannot be used.
  try { await users.deleteUser(uid); }
  catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
  const batch = db.batch();
  batch.delete(employeeRef);
  batch.delete(identityRef);
  if (indexData.exists) batch.delete(index);
  batch.delete(db.collection('leaderboard').doc(id));
  batch.delete(requestRef);
  await batch.commit();
  await db.recursiveDelete(db.collection('user_notifications').doc(id));
  process.stdout.write(`Deleted Auth ID, employee profile, auth index, leaderboard and inbox for ${id}.\nHistorical reports and audit logs retained for organizational records; review retention policy.\n`);
}
run().catch(e => { process.stderr.write(`ERROR: ${e.message}\n`); process.exitCode = 1; });

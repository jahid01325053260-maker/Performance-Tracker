import {onRequest} from 'firebase-functions/v2/https';
import {app} from './server.js';

// Region must match lib/services/api.dart. This function is the sole privileged
// Firestore gateway; Firebase Admin SDK never runs in the Flutter application.
export const api = onRequest({region: 'us-central1', memory: '512MiB',
  timeoutSeconds: 120, maxInstances: 12, cors: false}, app);

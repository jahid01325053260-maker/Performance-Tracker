# Firebase Setup

এই প্রজেক্ট এখন **Spark Free** সংস্করণ। আগের Cloud Functions সংক্রান্ত নির্দেশনা বাতিল।

পূর্ণ বাংলা সেটআপ গাইড: **[spark_free_setup_bn.md](spark_free_setup_bn.md)**

এখন দরকার Firebase Authentication Email/Password + Cloud Firestore + পরীক্ষিত Firestore Rules। Deploy command (নিরাপদে backup/staging test করার পরে):

```bash
firebase deploy --only firestore:rules --project performance-tracker-66b42
```

**Cloud Functions deploy করবেন না।**

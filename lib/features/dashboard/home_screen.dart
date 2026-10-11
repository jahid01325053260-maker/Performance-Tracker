import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/report_years.dart';
import '../../core/submission_deadline.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme.dart';
import '../../services/session.dart';
import '../../services/api.dart';
import '../../models/entities.dart';
import '../../services/notification_service.dart';
import '../notifications/notifications_screen.dart';
import '../auth/login_screen.dart' show showMessage;
import '../../services/calculations.dart';
import '../performance/submission_screen.dart';
import '../performance/my_reports_screen.dart';
import 'month_view_screen.dart';
import 'manager_team_screen.dart';
import 'individual_view_screen.dart';
import '../employees/directory_screen.dart';
import '../ranking/ranking_screen.dart';
import '../targets/targets_screen.dart';
import '../reports/export_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key,required this.session});
  final Session session;
  @override State<HomeScreen> createState()=>_HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Object>> summary;
  StreamSubscription<Map<String, int>>? rankingListener;
  StreamSubscription? profileListener;
  StreamSubscription? notificationListener;
  final DeliveredAlertStore deliveredAlertStore = DeliveredAlertStore();
  Timer? refreshTimer;
  void scheduleReload() {
    refreshTimer?.cancel();
    refreshTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(reload);
    });
  }
  @override void initState(){
    super.initState();reload();
    _listenForAlerts();
    rankingListener=widget.session.api.watchRankingCounts()
      .listen((_) => scheduleReload(), onError: (_) {});
    profileListener=widget.session.api.db.collection('employees')
      .doc(widget.session.user!.employeeId).snapshots()
      .listen((_) {
        widget.session.refresh().catchError((Object _) {});
        scheduleReload();
      }, onError: (_) {});
  }
  @override void dispose(){
    refreshTimer?.cancel();rankingListener?.cancel();profileListener?.cancel();
    notificationListener?.cancel();
    super.dispose();
  }
  Future<void> _listenForAlerts() async {
    if (!widget.session.api.isConfigured) return;
    final uid = widget.session.api.auth.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    // On Android 13+ this requests permission before processing existing
    // reminders. Inbox delivery itself does NOT depend on OS permission.
    await DeviceAlerts.requestPermission();
    final delivered = await deliveredAlertStore.read(uid);
    if (!mounted) return;
    var firstSnapshot = true;
    notificationListener = widget.session.api.watchOwnAlerts()
        .asyncMap((messages) async {
      if (!mounted) return;
      final isInitial = firstSnapshot;
      firstSnapshot = false;
      final expiry = DateTime.now().subtract(const Duration(days: 30));
      var shownOnInitial = 0;
      var changed = false;
      // Messages are returned newest first. On first launch, surface recent
      // reminders missed while the app was closed (up to three banners).
      for (final message in messages) {
        final id = '${message['id'] ?? ''}';
        if (id.isEmpty || delivered.contains(id)) continue;
        final createdAt = message['createdAt'];
        if (createdAt is Timestamp && createdAt.toDate().isBefore(expiry)) {
          delivered.add(id);
          changed = true;
          continue;
        }
        if (isInitial && shownOnInitial >= 3) continue;
        final displayed = await DeviceAlerts.notify(
          '${message['title'] ?? 'Performance Tracker'}',
          '${message['body'] ?? ''}');
        if (displayed) {
          delivered.add(id);
          changed = true;
          if (isInitial) shownOnInitial++;
        } else if (mounted && defaultTargetPlatform == TargetPlatform.android) {
          // Notifications are disabled, but the user still has an in-app inbox.
          showMessage(context, 'New report reminder. Open Notifications to read it. '
            'Enable notification permission for phone alerts.');
          break;
        }
      }
      if (changed) await deliveredAlertStore.write(uid, delivered);
    }).listen((_) {}, onError: (Object error) {
      if (mounted) showMessage(context,
        'Could not load reminders. Open Notifications to view the error.');
    });
  }

  void reload(){summary=Future.wait<Object>([widget.session.api.records(),widget.session.api.employees()]);}
  void visit(Widget page) async { await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>page)); if(mounted)setState(reload); }
  bool sendingQuickAlert = false;
  Future<void> sendAlertsLatestDuePeriod() async {
    if (sendingQuickAlert || widget.session.user?.isAdmin != true) { return; }
    final today = DateTime.now();
    // The most recently completed reporting month with a passed 10th deadline.
    final dueMonth = DateTime(today.year, today.month - (today.day >= 10 ? 1 : 2), 1);
    final period = '${dueMonth.year}-${dueMonth.month.toString().padLeft(2, '0')}';
    if (!reminderIsDue(period, today)) { return; }
    final confirm = await showDialog<bool>(context: context, builder: (dialog) =>
      AlertDialog(
        title: const Text('Alert not submitted officers?'),
        content: Text('Send a report reminder for ${readablePeriod(period)}? '
          'The deadline is the 10th of the following month. '
          'Notifications appear in their in-app inbox and as a local '
          'notification while the app is running; closed-app push requires a trusted FCM sender.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('SEND ALERT')),
        ],
      ));
    if (confirm != true || !mounted) { return; }
    setState(() => sendingQuickAlert = true);
    try {
      final count = await widget.session.api.alertNotSubmitted(period);
      if (mounted) { showMessage(context, count == 0
          ? 'No eligible officers need a reminder for this period.'
          : '$count reminder(s) added to employee inboxes.'); }
    } catch (e) {
      if (mounted) { showMessage(context, 'Unable to send reminders: $e'); }
    } finally {
      if (mounted) { setState(() => sendingQuickAlert = false); }
    }
  }

  Future<void> confirmExit() async {
    final action = await showDialog<String>(context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Exit Application?'),
        content: const Text('Do you want to exit Performance Tracker? '
          'Your current session will remain signed in unless you log out.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, 'cancel'),
            child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(dialog, 'logout'),
            child: const Text('LOGOUT')),
          FilledButton(onPressed: () => Navigator.pop(dialog, 'exit'),
            child: const Text('EXIT')),
        ],
      ));
    if (!mounted) return;
    if (action == 'logout') widget.session.logout();
    if (action == 'exit') {
      // Programmatic app exit is appropriate on Android, not on iOS.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await SystemNavigator.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Close the application window using the system control.')));
      }
    }
  }

  @override Widget build(BuildContext context){
    final me=widget.session.user!;
    final adminStyle=me.isAdmin||me.isManagement;
    final actions=<({String title,IconData icon,Widget Function() page})>[
      if(!adminStyle)(title:'New Submission',icon:Icons.add_circle_outline,page:()=>SubmissionScreen(session:widget.session)),
      if(adminStyle)(title:'Month View',icon:Icons.calendar_month,page:()=>MonthViewScreen(session:widget.session)),
      (title:adminStyle?'Individual View':'Officer List',icon:Icons.people_outline,page:()=>adminStyle ? IndividualViewScreen(session:widget.session) : DirectoryScreen(session:widget.session)),
      if(adminStyle)(title:'Monthly PDF / Export',icon:Icons.picture_as_pdf_outlined,page:()=>ExportScreen(session:widget.session)),
      if(adminStyle)(title:'Not Submitted',icon:Icons.person_off_outlined,page:()=>NotSubmittedScreen(session:widget.session)),
      if(adminStyle)(title:'Trend Chart',icon:Icons.show_chart,page:()=>TrendScreen(session:widget.session)),
      if(!adminStyle)(title:'Monthly Target',icon:Icons.flag_outlined,page:()=>TargetsScreen(session:widget.session)),
      if(!adminStyle)(title:'My Report',icon:Icons.description_outlined,page:()=>MyReportsScreen(session:widget.session)),
      if(!adminStyle)(title:'Export My Reports',icon:Icons.ios_share_outlined,page:()=>ExportScreen(session:widget.session)),
      (title:'Ranking',icon:Icons.emoji_events_outlined,page:()=>RankingScreen(session:widget.session)),
      if(adminStyle)(title:'Officer List',icon:Icons.groups_outlined,page:()=>DirectoryScreen(session:widget.session)),
      if(adminStyle)(title:'Manager Team',icon:Icons.supervisor_account_outlined,page:()=>ManagerTeamScreen(session:widget.session)),
      if(adminStyle)(title:'Targets',icon:Icons.flag_outlined,page:()=>TargetsScreen(session:widget.session)),
      (title:'Notifications',icon:Icons.notifications_outlined,page:()=>NotificationsScreen(session:widget.session)),
      (title:'Settings',icon:Icons.settings_outlined,page:()=>SettingsScreen(session:widget.session)),
    ];
    final width=MediaQuery.sizeOf(context).width;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) confirmExit();
      },
      child: Scaffold(appBar:AppBar(title:Text(adminStyle?(me.isAdmin?'Control Panel (ADMIN)':'Manager Dashboard'):'Performance Tracker'),
      actions:[IconButton(tooltip:'Refresh',onPressed:()=>setState(reload),icon:const Icon(Icons.refresh)), IconButton(tooltip:'Profile / settings',onPressed:()=>visit(SettingsScreen(session:widget.session)),icon:const Icon(Icons.settings_outlined))]),
      body:RefreshIndicator(onRefresh:()async{setState(reload);await summary;},child:ListView(padding:const EdgeInsets.all(16),children:[
        Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:1100),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Welcome, ${me.name}',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold,color:Palette.dark)),
          const SizedBox(height:4),Text('${me.role}  •  ${me.displayBranch}  •  ${me.displayZone}',style:const TextStyle(color:Palette.muted)),
          const SizedBox(height:16),FutureBuilder<List<Object>>(future:summary,builder:(context,snapshot){
            if(snapshot.hasError) return SectionCard(child:Column(children:[const Text('Unable to load live data'),Text('${snapshot.error}'),TextButton(onPressed:()=>setState(reload),child:const Text('Retry'))]));
            if(!snapshot.hasData)return const SectionCard(child:Center(child:Padding(padding:EdgeInsets.all(22),child:CircularProgressIndicator())));
            final records=snapshot.data![0] as List<CardRecord>;
            final employees=snapshot.data![1] as List<Employee>;
            final period=periodOf(DateTime.now());
            final count=countCards(records,reportingPeriod:period,employeeId:adminStyle?null:me.employeeId);
            final target=me.monthlyTarget;
            final achievement=Achievement(count,target);
            return Column(children:[
              Row(children:[Expanded(child:_StatCard(title:'Cards this month',value:'$count',icon:Icons.credit_card)),const SizedBox(width:10),
                Expanded(child:_StatCard(title:adminStyle?'Approved officers':'Monthly target',value:adminStyle?'${employees.where((e)=>e.isOfficer&&ApiClient.isDirectoryApproved(e.status)).length}':'$target',icon:Icons.flag_outlined))]),
              if (!adminStyle) ...[const SizedBox(height:10),
                _StatCard(title:'Total Cards (All Time)',value:'${countCards(records, employeeId:me.employeeId)}',icon:Icons.assessment_outlined)],
              const SizedBox(height:10),if(!adminStyle) SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('TARGET ACHIEVEMENT • ${readablePeriod(period)}',style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),
                Text(achievement.label,style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold,color:Palette.primary)),const SizedBox(height:8),
                LinearProgressIndicator(value:achievement.progress,minHeight:9,borderRadius:BorderRadius.circular(12)),
                if(achievement.below50)Padding(padding:const EdgeInsets.only(top:8),child:Text('Below 50% • ${achievement.needsFor50} card(s) needed to reach 50%',style:const TextStyle(color:Palette.red))),
              ])),
            ]);
          }),
          const SizedBox(height:16),Text(adminStyle?'MAIN ACTIONS':'QUICK ACTIONS',style:const TextStyle(fontWeight:FontWeight.bold,color:Palette.dark)),const SizedBox(height:10),
          GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:actions.length,
            gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:width>=970?4:width>=540?3:2,mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:width>=540?2.2:1.6),
            itemBuilder:(context,i){final a=actions[i];return Card(clipBehavior:Clip.antiAlias,child:InkWell(onTap:()=>visit(a.page()),child:Padding(padding:const EdgeInsets.all(12),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(a.icon,color:Palette.primary,size:30),const SizedBox(height:10),if(a.title == 'Not Submitted' && me.isAdmin)
              Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                const Flexible(child:Text('Not Submitted',textAlign:TextAlign.center,
                  style:TextStyle(fontWeight:FontWeight.w600))),
                IconButton(tooltip:'Send alert to officers missing their reports',
                  onPressed:sendingQuickAlert?null:sendAlertsLatestDuePeriod,
                  icon:sendingQuickAlert?const SizedBox(width:18,height:18,
                    child:CircularProgressIndicator(strokeWidth:2)):
                    const Icon(Icons.notification_add_outlined,color:Palette.primary)),
              ])
              else Text(a.title,textAlign:TextAlign.center,
                style:const TextStyle(fontWeight:FontWeight.w600))]))));}),
        ])))
      ]))));
  }
}
class _StatCard extends StatelessWidget {
  const _StatCard({required this.title,required this.value,required this.icon});
  final String title,value;final IconData icon;
  @override Widget build(BuildContext context)=>SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:Palette.primary),const SizedBox(height:12),Text(value,style:const TextStyle(fontSize:27,fontWeight:FontWeight.bold)),Text(title,maxLines:2,style:const TextStyle(color:Palette.muted))]));
}

class NotSubmittedScreen extends StatelessWidget {
  const NotSubmittedScreen({super.key,required this.session}); final Session session;
  @override Widget build(BuildContext context)=> _PeriodScopedScreen(session:session,title:'Not Submitted',isTrend:false);
}
class TrendScreen extends StatelessWidget {
  const TrendScreen({super.key,required this.session});final Session session;
  @override Widget build(BuildContext context)=>_PeriodScopedScreen(session:session,title:'Trend Chart',isTrend:true);
}
class _PeriodScopedScreen extends StatefulWidget {
  const _PeriodScopedScreen({required this.session,required this.title,required this.isTrend});
  final Session session;final String title;final bool isTrend;
  @override State<_PeriodScopedScreen> createState()=>_PeriodScopedScreenState();
}
class _PeriodScopedScreenState extends State<_PeriodScopedScreen> {
  late int year;
  late int month;
  late Future<List<Object>> future;
  @override void initState() {
    super.initState();
    final today = DateTime.now();
    final latestDue = DateTime(today.year,
        today.month - (today.day >= 10 ? 1 : 2), 1);
    year = widget.isTrend ? today.year : latestDue.year;
    month = widget.isTrend ? today.month : latestDue.month;
    load();
  }
  void load() {
    future = Future.wait<Object>([
      widget.session.api.employees(),
      widget.session.api.records(),
    ]);
  }
  bool sendingAlerts = false;
  Future<void> alertMissing() async {
    if (sendingAlerts) return;
    try {
      final resolved = await future;
      final period = '$year-${month.toString().padLeft(2,'0')}';
      if (!reminderIsDue(period, DateTime.now())) {
        if (mounted) showMessage(context, 'The reminder becomes available on the 10th of the following month.');
        return;
      }
      final records = resolved[1] as List<CardRecord>;
      final missing = (resolved[0] as List<Employee>)
        .where((e) => e.isOfficer && ApiClient.isDirectoryApproved(e.status) &&
            !didSubmit(records, e.employeeId, period)).toList();
      if (!mounted) return;
      if (missing.isEmpty) { showMessage(context, 'All officers have submitted.'); return; }
      final ok = await showDialog<bool>(context: context, builder: (dialog) =>
        AlertDialog(title: const Text('Send submission alerts?'),
          content: Text('Create an alert for ${missing.length} officers for ${readablePeriod(period)}? '
            'The monthly report deadline is the 10th of the following month. '
            'This free-plan feature cannot send background push to a closed app.'),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('CANCEL')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('SEND ALERTS'))]));
      if (ok != true || !mounted) return;
      setState(() => sendingAlerts = true);
      // Re-check immediately before publishing to avoid notifying recent submitters.
      final sent = await widget.session.api.alertNotSubmitted(period);
      if (mounted) showMessage(context, sent == 0
          ? 'No eligible officers need a reminder for this period.'
          : '$sent reminder(s) delivered to employee inboxes. '
              'Phone banners appear when the user opens the Android app and permits notifications.');
    } catch (error) {
      if (mounted) showMessage(context, 'Could not send alerts: $error');
    } finally {
      if (mounted) setState(() => sendingAlerts = false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.title),actions:[
    if (!widget.isTrend && widget.session.user?.isAdmin == true)
      IconButton(tooltip: 'Alert not submitted officers',
        onPressed: sendingAlerts ? null : alertMissing,
        icon: sendingAlerts ? const SizedBox(width:18,height:18,
          child: CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.notifications_active_outlined)),
  ]),body:Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:DropdownButtonFormField<int>(initialValue:year,decoration:const InputDecoration(labelText:'Year'),items:[for(final y in reportYears)DropdownMenuItem(value:y,child:Text('$y'))],onChanged:(y)=>setState(()=>year=y??year))),
    if(!widget.isTrend)...[const SizedBox(width:8),Expanded(child:DropdownButtonFormField<int>(initialValue:month,decoration:const InputDecoration(labelText:'Month'),items:[for(var i=1;i<=12;i++)DropdownMenuItem(value:i,child:Text(monthNames[i-1]))],onChanged:(m)=>setState(()=>month=m??month)))]])),
    Expanded(child:FutureBuilder<List<Object>>(future:future,builder:(context,s){if(s.hasError)return LoadError(message:'${s.error}',retry:()=>setState(load));if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final people=(s.data![0] as List<Employee>).where((e)=>e.isOfficer&&ApiClient.isDirectoryApproved(e.status)).toList();
      final records=s.data![1] as List<CardRecord>;
      if(widget.isTrend){final values=[for(var m=1;m<=12;m++)countCards(records,reportingPeriod:'$year-${m.toString().padLeft(2,'0')}')];
        final maxV=values.fold<int>(1,(a,b)=>a>b?a:b);
        return ListView(padding:const EdgeInsets.all(12),children:[SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Total ${values.fold<int>(0,(a,b)=>a+b)} • Peak $maxV'),const SizedBox(height:16),for(var i=0;i<12;i++)Padding(padding:const EdgeInsets.only(bottom:12),child:Row(children:[SizedBox(width:35,child:Text(monthNames[i].substring(0,3))),Expanded(child:LinearProgressIndicator(value:values[i]/maxV,minHeight:12,borderRadius:BorderRadius.circular(9))),const SizedBox(width:10),SizedBox(width:30,child:Text('${values[i]}'))]))]))]);}
      final period='$year-${month.toString().padLeft(2,'0')}';
      final missing=people.where((e)=>!didSubmit(records,e.employeeId,period)).toList();
      return ListView(children:[Padding(padding:const EdgeInsets.all(16),child:Text('${missing.length} officer(s) not submitted • ${readablePeriod(period)}',style:const TextStyle(fontWeight:FontWeight.bold))),
        for(final e in missing) ListTile(leading:CircleAvatar(child:Text(e.name.isEmpty?'?':e.name[0])),title:Text(e.name),subtitle:Text('${e.employeeId}  •  ${e.displayBranch}'),trailing:const Icon(Icons.warning_amber_outlined))]);
    }))
  ]));
}

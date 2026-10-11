import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/entities.dart';
import '../../services/calculations.dart';
import '../../services/session.dart';
import '../auth/login_screen.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key,required this.session,this.all=false});
  final Session session; final bool all;
  @override State<MyReportsScreen> createState()=>_MyReportsScreenState();
}
class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<CardRecord>> future;
  @override void initState(){super.initState();refresh();
    _updates=widget.session.api.watchRankingCounts().listen((_) => _liveRefresh(), onError: (_) {});}
  StreamSubscription<Map<String, int>>? _updates;
  Timer? _debounce;
  void _liveRefresh() {
    _debounce?.cancel();
    _debounce=Timer(const Duration(milliseconds: 650), () {
      if(mounted) setState(refresh);
    });
  }
  @override void dispose() {
    _debounce?.cancel();_updates?.cancel();
    
    super.dispose();
  }
  void refresh() {
    future = widget.session.api.records(
      employeeId: widget.all ? null : widget.session.user!.employeeId,
    );
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.all?'Month View':'My Reports'),actions:[IconButton(onPressed:()=>setState(refresh),icon:const Icon(Icons.refresh))]),
    body:FutureBuilder<List<CardRecord>>(future:future,builder:(context,s){if(s.hasError)return LoadError(message:'${s.error}',retry:()=>setState(refresh));if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final groups=<String,List<CardRecord>>{};
      for(final r in s.data!) {if(r.status=='deleted')continue;final key='${r.employeeId}|${r.reportingPeriod}';(groups[key]??=[]).add(r);}
      final keys=groups.keys.toList()..sort((a,b)=>b.split('|').last.compareTo(a.split('|').last));
      return keys.isEmpty?const Center(child:Text('No reports found')):ListView(padding:const EdgeInsets.all(12),children:[
        for(final key in keys)Card(child:ListTile(title:Text('${groups[key]!.first.employeeName} • ${readablePeriod(groups[key]!.first.reportingPeriod)}'),
          subtitle:Text('${countCards(groups[key]!)} 906 card(s) • ${groups[key]!.any((r)=>r.isNil)?'Includes NIL status':'Submitted'}'),
          trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>ReportDetailScreen(session:widget.session,items:groups[key]!))).then((_)=>setState(refresh))))
      ]);
    }));
}

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key,required this.session,required this.items});
  final Session session;final List<CardRecord> items;
  @override State<ReportDetailScreen> createState()=>_ReportDetailScreenState();
}
class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late Future<List<CardRecord>> future;
  @override void initState(){super.initState();reload();}
  void reload() {
    future = widget.session.api.records(
      employeeId: widget.items.first.employeeId,
      period: widget.items.first.reportingPeriod,
    );
  }
  Future<void> edit(CardRecord record)async{
    if (!widget.session.user!.isAdmin) return;
    final name=TextEditingController(text:record.applicantName),account=TextEditingController(text:record.accountNo),limit=TextEditingController(text:record.limit);
    try{
      final choice=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Edit report entry'),content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Applicant Name')),const SizedBox(height:8),TextField(controller:account,decoration:const InputDecoration(labelText:'A/C No')),const SizedBox(height:8),TextField(controller:limit,decoration:const InputDecoration(labelText:'Limit'))])),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(ctx,'delete'),child:const Text('Delete')),FilledButton(onPressed:()=>Navigator.pop(ctx,'save'),child:const Text('Save'))]));
      if(choice=='save')await widget.session.api.updateRecord(record.id,{'applicantName':name.text,'accountNo':account.text,'limit':limit.text});
      if(choice=='delete'){
        if(!mounted)return;
        final confirm=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Delete entry?'),content:const Text('This removes the record from all totals. Please confirm this change.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete'))]));
        if(confirm==true)await widget.session.api.deleteRecord(record.id);
      }
      if(mounted)setState(reload);
    }catch(e){if(mounted)showMessage(context,'$e');}
    finally{name.dispose();account.dispose();limit.dispose();}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('Report • ${readablePeriod(widget.items.first.reportingPeriod)}'),actions:[IconButton(onPressed:()=>setState(reload),icon:const Icon(Icons.refresh))]),body:FutureBuilder<List<CardRecord>>(future:future,builder:(context,s){if(s.hasError)return LoadError(message:'${s.error}',retry:()=>setState(reload));if(!s.hasData)return const Center(child:CircularProgressIndicator());
    final items=s.data!.where((e)=>e.status!='deleted').toList();return ListView(padding:const EdgeInsets.all(12),children:[SectionCard(child:Text('Valid cards: ${countCards(items)}  •  ${widget.items.first.employeeName}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
      for(var i=0;i<items.length;i++)Card(child:ListTile(leading:CircleAvatar(child:Text('${items[i].slNo > 0 ? items[i].slNo : i + 1}')),title:Text(items[i].isNil?'NIL • Zero Approval':items[i].applicantName),subtitle:Text('${items[i].accountNo}  •  Amount: ${items[i].limit.isEmpty ? 'Not provided' : items[i].limit}'
        '${items[i].source == 'pdf' ? '\nPDF Period: ${items[i].periodStart} to ${items[i].periodEnd}  •  Verify: ${items[i].verify}' : ''}'),trailing:widget.session.user!.isAdmin?IconButton(onPressed:()=>edit(items[i]),icon:const Icon(Icons.edit_outlined)):null))]);
  }));
}

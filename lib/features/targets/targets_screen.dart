import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/report_years.dart';
import '../../core/theme.dart';
import '../../models/entities.dart';
import '../../services/calculations.dart';
import '../../services/session.dart';
import '../../services/report_scope.dart';
import '../auth/login_screen.dart';

class TargetsScreen extends StatefulWidget {
  const TargetsScreen({super.key,required this.session});final Session session;
  @override State<TargetsScreen> createState()=>_TargetsScreenState();
}
class _TargetsScreenState extends State<TargetsScreen> {
  int year=DateTime.now().year,month=DateTime.now().month;
  late Future<List<Object>> future;
  @override void initState(){super.initState();reload();
    _updates=widget.session.api.watchRankingCounts().listen((_) => _liveRefresh(), onError: (_) {});}
  StreamSubscription<Map<String, int>>? _updates;
  Timer? _debounce;
  void _liveRefresh() {
    _debounce?.cancel();
    _debounce=Timer(const Duration(milliseconds: 650), () {
      if(mounted) setState(reload);
    });
  }
  @override void dispose() {
    _debounce?.cancel();_updates?.cancel();
    
    super.dispose();
  }
  void reload() {
    future = Future.wait<Object>([
      widget.session.api.employees(),
      widget.session.api.records(),
      widget.session.api.targets(),
    ]);
  }
  String get period => '$year-${month.toString().padLeft(2,'0')}';
  Future<void> setTarget(Employee e,EmployeeTarget? existing) async {
    final cards=TextEditingController(text:'${existing?.targetCards??e.monthlyTarget}');
    final yearly=TextEditingController(text:'${existing?.yearlyTargetCards??e.yearlyTarget}');
    try {
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('Set Target • ${e.name}'),content:Column(mainAxisSize:MainAxisSize.min,children:[Text('This target repeats EVERY month (all years).'),const SizedBox(height:14),TextField(controller:cards,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Monthly target (cards)')),const SizedBox(height:8),TextField(controller:yearly,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Yearly target (cards)'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))]));
      if(ok!=true)return;
      final m=int.tryParse(cards.text),y=int.tryParse(yearly.text);
      if(m==null||y==null||m<0||y<0)throw const FormatException('Targets must be non-negative integers');
      await widget.session.api.setTarget(e.employeeId,period,m,y);
      if(mounted){showMessage(context,'Target saved');setState(reload);}
    }catch(err){if(mounted)showMessage(context,'$err');}finally{cards.dispose();yearly.dispose();}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Monthly Targets'),actions:[IconButton(onPressed:()=>setState(reload),icon:const Icon(Icons.refresh))]),body:Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:DropdownButtonFormField<int>(initialValue:month,decoration:const InputDecoration(labelText:'Month'),items:[for(var i=1;i<=12;i++)DropdownMenuItem(value:i,child:Text(monthNames[i-1]))],onChanged:(v)=>setState(()=>month=v??month))),const SizedBox(width:8),
      SizedBox(width:115,child:DropdownButtonFormField<int>(initialValue:year,decoration:const InputDecoration(labelText:'Year'),items:[for(final y in reportYears)DropdownMenuItem(value:y,child:Text('$y'))],onChanged:(v)=>setState(()=>year=v??year))) ])),
    Expanded(child:FutureBuilder<List<Object>>(future:future,builder:(context,s){if(s.hasError)return LoadError(message:'${s.error}',retry:()=>setState(reload));if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final emps=permittedReportOfficers(widget.session.user!,
        s.data![0] as List<Employee>);
      final records=s.data![1] as List<CardRecord>;
      return ListView(padding:const EdgeInsets.all(12),children:[for(final e in emps)Builder(builder:(context){
        final t=EmployeeTarget(employeeId:e.employeeId,reportingPeriod:period,
          targetCards:e.monthlyTarget,yearlyTargetCards:e.yearlyTarget);
        final monthlyCards=countCards(records,employeeId:e.employeeId,reportingPeriod:period);
        final yearlyCards=countCardsForYear(records, e.employeeId, year);
        final achievement=Achievement(monthlyCards,e.monthlyTarget);
        final annual=Achievement(yearlyCards,e.yearlyTarget);
        return SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(e.name,style:const TextStyle(fontWeight:FontWeight.bold))),if(widget.session.user!.isAdmin)TextButton(onPressed:()=>setTarget(e,t),child:const Text('Set Target'))]),
          Text('${e.employeeId} • Monthly: ${achievement.achieved}/${achievement.target} cards • ${achievement.label}'),
          const SizedBox(height:8),LinearProgressIndicator(value:achievement.progress),
          const SizedBox(height:10),
          Text('Year $year: ${annual.achieved}/${annual.target} cards • ${annual.label}'),
          const SizedBox(height:6),LinearProgressIndicator(value:annual.progress),
          if(achievement.below50)Text('Below 50% • Need ${achievement.needsFor50} card(s)',style:const TextStyle(color:Palette.red))
        ]));
      })]);
    }))
  ]));
}

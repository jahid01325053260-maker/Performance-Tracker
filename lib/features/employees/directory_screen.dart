import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import '../../core/theme.dart';
import '../../models/entities.dart';
import '../../services/session.dart';
import '../../services/profile_photo_processor.dart';
import '../auth/login_screen.dart';
import 'sales_manager_picker.dart';
import 'admin_account_actions.dart';
import 'profile_photo_adjust_screen.dart';

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key,required this.session}); final Session session;
  @override State<DirectoryScreen> createState()=>_DirectoryScreenState();
}
class _DirectoryScreenState extends State<DirectoryScreen> {
  final search=TextEditingController();String filter='All';
  late Future<List<Employee>> future;
  StreamSubscription? _directoryChanges;
  Timer? _timer;
  @override void initState(){super.initState();refresh();
    final viewer=widget.session.user!;
    _directoryChanges=(viewer.isAdmin
      ? widget.session.api.db.collection('employees')
      : widget.session.api.db.collection('employees').where('status',whereIn:
          ['Approved','APPROVED','approved','']))
      .snapshots().listen((_) {
        _timer?.cancel();
        _timer=Timer(const Duration(milliseconds: 650), () {
          if(mounted)setState(refresh);
        });
      }, onError: (_) {});
  }
  void refresh() {
    future = widget.session.api.employees();
  }
  @override void dispose(){_timer?.cancel();_directoryChanges?.cancel();search.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Employee Directory'),actions:[IconButton(onPressed:()=>setState(refresh),icon:const Icon(Icons.refresh))]),body:Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:TextField(controller:search,onChanged:(_)=>setState((){}),decoration:InputDecoration(prefixIcon:const Icon(Icons.search),labelText:'Search name, ID, branch, zone',suffixIcon:IconButton(onPressed:()=>setState(search.clear),icon:const Icon(Icons.clear))))),
    SizedBox(height:44,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),children:[for(final role in ['All','USER','Sales Manager','AGM','DGM','ADMIN'])Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(role=='USER'?'Officers':role),selected:filter==role,onSelected:(_)=>setState(()=>filter=role)))])),
    Expanded(child:FutureBuilder<List<Employee>>(future:future,builder:(ctx,s){if(s.hasError)return LoadError(message:'${s.error}',retry:()=>setState(refresh));if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final query=search.text.trim().toLowerCase();
      final items=s.data!.where((e)=>(filter=='All'||e.role.toLowerCase()==filter.toLowerCase())&&[e.employeeId,e.name,e.branch,e.zone,e.salesManager,e.department].any((v)=>v.toLowerCase().contains(query))).toList()
        ..sort((a,b)=>a.name.compareTo(b.name));
      return ListView(children:[Padding(padding:const EdgeInsets.all(12),child:Text('Showing ${items.length} of ${s.data!.length} employees',style:const TextStyle(color:Palette.muted))),if(items.isEmpty)const Center(child:Padding(padding:EdgeInsets.all(40),child:Text('No matching employees'))),
        for(final e in items)Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:ListTile(
          leading:EmployeeAvatar(employee:e),title:Text(e.name),subtitle:Text('${e.employeeId}  •  ${e.role}\n${e.displayBranch}  •  ${e.displayZone}'),isThreeLine:true,
          trailing: widget.session.user!.isAdmin && e.employeeId != widget.session.user!.employeeId && e.status == 'Approved'
            ? PopupMenuButton<String>(
                tooltip: 'Employee actions',
                onSelected: (value) async {
                  if (value == 'role') {
                    final saved = await showAdminRoleEditor(context, widget.session, e);
                    if (saved && mounted) setState(refresh);
                  }
                  if (value == 'reset') {
                    await adminPasswordResetAction(context, widget.session, e);
                  }
                  if (value == 'delete') {
                    final changed = await adminDeleteAction(context, widget.session, e);
                    if (changed && mounted) setState(refresh);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'role', child: Text('Change role')),
                  PopupMenuItem(value: 'reset', child: Text('Reset password / recovery')),
                  PopupMenuItem(value: 'delete', child: Text('Disable and request ID deletion')),
                ],
              ) : const Icon(Icons.chevron_right),
          onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>EmployeeProfileScreen(session:widget.session,id:e.employeeId))).then((_) { if (mounted) setState(refresh); }),
        ))]);
    }))
  ]));
}

class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({super.key,required this.employee,this.radius=22});final Employee employee;final double radius;
  @override Widget build(BuildContext context){
    Uint8List? bytes;
    try{if(employee.profileImage.isNotEmpty && !employee.profileImage.startsWith('http')) {
      bytes=base64Decode(employee.profileImage.contains(',')?employee.profileImage.split(',').last:employee.profileImage);
    }}catch(_){bytes=null;}
    return CircleAvatar(radius:radius,backgroundColor:Palette.pale,
      backgroundImage:bytes!=null?MemoryImage(bytes):employee.profileImage.startsWith('https://')?NetworkImage(employee.profileImage):null,
      child:bytes==null&&!employee.profileImage.startsWith('https://')?Text(employee.name.isEmpty?'?':employee.name[0].toUpperCase(),style:const TextStyle(color:Palette.primary,fontWeight:FontWeight.bold)):null);
  }
}

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key,required this.session,required this.id});final Session session;final String id;
  @override State<EmployeeProfileScreen> createState()=>_EmployeeProfileScreenState();
}
class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  late Future<Employee> future;
  @override void initState(){super.initState();load();}
  void load() {
    future = widget.session.api.profile(widget.id);
  }
  Future<void> updatePhoto(Employee e) async {
    if(!widget.session.user!.isAdmin && widget.session.user!.employeeId != e.employeeId) {
      return;
    }
    try {
      final chosen = await FilePicker.pickFiles(type: FileType.image);
      if(chosen.isEmpty) {
        return;
      }
      final bytes = await chosen.single.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if(decoded == null) {
        throw const FormatException('Unsupported image format');
      }
      if(!mounted) {
        return;
      }
      final adjustment = await Navigator.push<ProfilePhotoAdjustment>(
        context,
        MaterialPageRoute(
          builder: (_) => ProfilePhotoAdjustScreen(source: decoded),
        ),
      );
      if(adjustment == null || !mounted) {
        return;
      }
      final cropped = ProfilePhotoProcessor.applyAdjustment(decoded, adjustment);
      final optimized = ProfilePhotoProcessor.compressToTarget(cropped);
      await widget.session.api.editProfile(
        e.employeeId,
        {'profileImage': base64Encode(optimized)},
      );
      if(mounted) {
        showMessage(
          context,
          'Profile photo updated • ${(optimized.length / 1024).toStringAsFixed(1)} KB',
        );
        setState(load);
      }
    } catch(error) {
      if(mounted) {
        showMessage(context,'Photo update failed: $error');
      }
    }
  }
  Future<void> edit(Employee e) async {
    final allowed=widget.session.user!.isAdmin||widget.session.user!.employeeId==e.employeeId;
    if(!allowed)return;
    final values={'name':e.name,'mobile':e.mobile,'officialNumber':e.officialNumber,'email':e.email,if(widget.session.user!.isAdmin)...{'branch':e.branch,'zone':e.zone,'department':e.department}};
    final controllers={for(final kv in values.entries)kv.key:TextEditingController(text:kv.value)};
    try{
      final saved=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Edit Profile'),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final f in controllers.entries)Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:f.value,decoration:InputDecoration(labelText:f.key))),
      ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))]));
      if(saved!=true)return;
      await widget.session.api.editProfile(e.employeeId,{for(final kv in controllers.entries)kv.key:kv.value.text.trim()});
      if(mounted){showMessage(context,'Profile updated');setState(load);}
    }catch(err){if(mounted)showMessage(context,'$err');}
    finally{for(final c in controllers.values){c.dispose();}}
  }
  Future<void> assignManager(Employee officer) async {
    try {
      final employees = await widget.session.api.employees();
      if (!mounted) return;
      final managers = employees.where((e) =>
        e.role.toLowerCase() == 'sales manager' &&
        e.status.toLowerCase() == 'approved').toList();
      String selected = managers.any((m) => m.employeeId == officer.managerId)
          ? officer.managerId : '';
      final chosen = await showDialog<String>(context: context, builder: (ctx) =>
        StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Assign Sales Manager'),
          content: SizedBox(width: 410, child: DropdownButtonFormField<String>(
            initialValue: selected, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Assigned manager'),
            items: [const DropdownMenuItem(value: '', child: Text('No manager')),
              for (final m in managers) DropdownMenuItem(value: m.employeeId,
                child: Text('${m.name} (${m.employeeId})',
                  overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setDialog(() => selected = v ?? ''),
          )),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('SAVE'))],
        )));
      if (chosen == null || !mounted) return;
      final manager = managers.where((m) => m.employeeId == chosen).firstOrNull;
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) =>
        AlertDialog(title: const Text('Update team assignment?'),
          content: const Text('This changes the officer profile and existing '
            'report ownership for manager-only access. Back up Firestore first.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('CONFIRM'))]));
      if (confirmed != true) return;
      final updated = await widget.session.api.assignSalesManager(officer, manager);
      if (mounted) {
        showMessage(context, 'Manager assigned • $updated historical reports linked');
        setState(load);
      }
    } catch (error) {
      if (mounted) showMessage(context, 'Manager assignment failed: $error');
    }
  }

  Future<void> requestManagerChange(Employee employee) async {
    SalesManagerOption? chosen;
    final proceed = await showDialog<bool>(context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: const Text('Update Sales Manager'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SalesManagerPicker(api: widget.session.api,
            initialManagerId: employee.managerId,
            onChanged: (manager) => setDialog(() => chosen = manager)),
          const SizedBox(height: 12),
          const Text('After you select a manager, ADMIN will review the change. '
            'Reports stay with their current team until approval.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL')),
          FilledButton(onPressed: chosen == null ? null : () => Navigator.pop(ctx, true),
            child: const Text('REQUEST UPDATE')),
        ],
      )),
    );
    if (proceed != true || chosen == null) return;
    try {
      await widget.session.api.requestSalesManagerChange(chosen!.employeeId);
      if (mounted) showMessage(context, 'Sales Manager update sent to ADMIN for approval.');
    } catch (e) {
      if (mounted) showMessage(context, 'Manager update failed: $e');
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Employee Profile'),actions:[IconButton(onPressed:()=>setState(load),icon:const Icon(Icons.refresh))]),
    body:FutureBuilder<Employee>(future:future,builder:(ctx,s){if(s.hasError)return LoadError(message:'${s.error}',retry:()=>setState(load));if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final e=s.data!;return Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(padding:const EdgeInsets.all(16),children:[
        SectionCard(child:Column(children:[EmployeeAvatar(employee:e,radius:55),
          if(widget.session.user!.isAdmin||widget.session.user!.employeeId==e.employeeId)TextButton.icon(onPressed:()=>updatePhoto(e),icon:const Icon(Icons.camera_alt_outlined),label:const Text('Change Photo')),
          const SizedBox(height:12),Text(e.name,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Text('${e.role} • ${e.status}'),Text(e.employeeId),
          const SizedBox(height:12),if(widget.session.user!.isAdmin||widget.session.user!.employeeId==e.employeeId)FilledButton.icon(onPressed:()=>edit(e),icon:const Icon(Icons.edit),label:const Text('Edit Profile')),
          if (e.isOfficer && widget.session.user!.employeeId == e.employeeId &&
              !widget.session.user!.isAdmin)
            Padding(padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: () => requestManagerChange(e),
                icon: const Icon(Icons.people_outline),
                label: const Text('Change Sales Manager'),
              )),
          if (widget.session.user!.isAdmin && e.isOfficer)
            Padding(padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: () => assignManager(e),
                icon: const Icon(Icons.supervisor_account_outlined),
                label: const Text('Assign Sales Manager'),
              )),
          if (widget.session.user!.isAdmin && e.employeeId != widget.session.user!.employeeId && e.status == 'Approved')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final updated = await showAdminRoleEditor(context, widget.session, e);
                  if (updated && mounted) setState(load);
                },
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Change employee role'),
              ),
            ),
        ])),
        SectionCard(child:Column(children:[
          _field('Branch',e.displayBranch),_field('Zone',e.displayZone),_field('Department',e.department),
          if(e.isOfficer)_field('Sales Manager',e.salesManager),
          _field('Mobile',e.mobile,copyable:true),
          _field('Official Number',e.officialNumber,copyable:true),
          _field('Recovery email',e.email,copyable:true),
          if(e.isOfficer)_field('Monthly Target',e.monthlyTarget>0?'${e.monthlyTarget} cards (repeats monthly)':'No Target Assigned'),
          if(e.isOfficer)_field('Yearly Target',e.yearlyTarget>0?'${e.yearlyTarget} cards (annual default)':'No Target Assigned'),
        ])),
      ])));
    }));

  Future<void> _copyContact(String label, String value) async {
    final text=value.trim();
    if(text.isEmpty){
      showMessage(context,'No $label available');
      return;
    }
    await Clipboard.setData(ClipboardData(text:text));
    if(mounted) {
      showMessage(context,'$label copied');
    }
  }

  Widget _field(String label,String value,{bool copyable=false})=>ListTile(
    dense:true,
    title:Text(label,style:const TextStyle(color:Palette.muted)),
    subtitle:Text(value.isEmpty?'N/A':value),
    trailing:copyable&&value.trim().isNotEmpty?IconButton(
      tooltip:'Copy $label',
      onPressed:()=>_copyContact(label,value),
      icon:const Icon(Icons.copy_outlined),
    ):null,
  );
}


/// Shared ADMIN action used in directory and profile screens.
/// Persisted on Firestore in an atomic transaction, not only in local widgets.
Future<bool> showAdminRoleEditor(
  BuildContext context,
  Session session,
  Employee employee,
) async {
  if (session.user?.isAdmin != true ||
      session.user?.employeeId == employee.employeeId ||
      employee.status != 'Approved') {
    return false;
  }
  var selected = employee.role;
  const roles = ['USER', 'Sales Manager', 'AGM', 'DGM', 'ADMIN'];
  final confirmation = await showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setDialogState) => AlertDialog(
        title: const Text('Edit employee role'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 410),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(employee.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(employee.employeeId),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: roles.contains(selected) ? selected : 'USER',
                decoration: const InputDecoration(labelText: 'Assigned role'),
                items: [for (final role in roles)
                  DropdownMenuItem(value: role, child: Text(role))],
                onChanged: (value) => setDialogState(() => selected = value ?? selected),
              ),
              const SizedBox(height: 12),
              const Text('This changes access to reports, targets and admin '
                'controls. The user may need to reopen the app to see the new menu.',
                style: TextStyle(fontSize: 12, color: Palette.muted)),
            ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('CANCEL')),
          FilledButton(onPressed: selected == employee.role ? null :
            () => Navigator.pop(dialog, selected),
            child: const Text('REVIEW CHANGE')),
        ],
      ),
    ),
  );
  if (confirmation == null || !context.mounted) return false;
  final verified = await showDialog<bool>(context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Confirm role change'),
      content: Text('Change ${employee.name} (${employee.employeeId}) '
          'from ${employee.role} to $confirmation?'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false),
          child: const Text('CANCEL')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true),
          child: const Text('CONFIRM'))],
    ));
  if (verified != true) return false;
  try {
    await session.api.changeEmployeeRole(employee.employeeId, confirmation);
    if (context.mounted) showMessage(context, '${employee.name}: role updated to $confirmation');
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, 'Role update failed: $e');
    return false;
  }
}

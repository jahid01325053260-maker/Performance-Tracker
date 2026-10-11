import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/entities.dart';
import '../../services/api.dart';
import '../../services/calculations.dart';
import '../../services/session.dart';
import '../employees/directory_screen.dart';
import 'month_view_screen.dart';

/// Mirrors the native app's "Sales Managers & Teams" fullscreen filter:
/// manager summary -> View Officers / Filter Main Dashboard.
/// Membership prefers stable managerId but supports legacy salesManager names.
class ManagerTeamScreen extends StatefulWidget {
  const ManagerTeamScreen({super.key, required this.session});
  final Session session;
  @override
  State<ManagerTeamScreen> createState() => _ManagerTeamScreenState();
}

class _ManagerTeamScreenState extends State<ManagerTeamScreen> {
  final search = TextEditingController();
  late Future<(List<Employee>, List<CardRecord>)> data;
  StreamSubscription<Map<String,int>>? _live;
  Timer? _timer;

  @override
  void initState() {
    super.initState(); _reload();
    _live=widget.session.api.watchRankingCounts().listen((_) {
      _timer?.cancel();
      _timer=Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(_reload);
      });
    },onError: (_) {});
  }
  void _reload() {
    data = () async {
      final people = await widget.session.api.employees();
      final reports = await widget.session.api.records();
      return (people, reports);
    }();
  }
  @override
  void dispose() { _timer?.cancel(); _live?.cancel(); search.dispose(); super.dispose(); }


  Future<void> _choose(Employee manager, List<Employee> officers) async {
    final action = await showDialog<String>(context: context, builder: (ctx) =>
      AlertDialog(
        title: Text('Team: ${manager.name}'),
        content: Text('Select an action for ${manager.name}.\n'
          '${officers.length} officer(s) in this team.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, 'officers'),
            child: Text('VIEW OFFICERS (${officers.length})')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'filter'),
            child: const Text('FILTER DASHBOARD')),
        ],
      ));
    if (!mounted) { return; }
    if (action == 'officers') {
      Navigator.push<void>(context, MaterialPageRoute(builder: (_) =>
        _TeamOfficers(session: widget.session, manager: manager, officers: officers)));
    } else if (action == 'filter') {
      Navigator.push<void>(context, MaterialPageRoute(builder: (_) =>
        MonthViewScreen(session: widget.session,
          managerId: manager.employeeId, managerName: manager.name)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales Managers & Teams'),
      actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh),
        onPressed: () => setState(_reload))]),
    body: FutureBuilder<(List<Employee>, List<CardRecord>)>(future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return LoadError(message: '${snapshot.error}',
            retry: () => setState(_reload));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (allPeople, reports) = snapshot.data!;
        final viewer = widget.session.user!;
        final managers = allPeople.where((e) => e.role.toLowerCase() == 'sales manager' &&
          ApiClient.isDirectoryApproved(e.status) &&
          (viewer.isAdmin || {'agm','dgm'}.contains(viewer.role.trim().toLowerCase()) || viewer.employeeId == e.employeeId)).toList();
        final filtered = managers.where((m) {
          final q = search.text.trim().toLowerCase();
          return m.name.toLowerCase().contains(q) ||
            m.branch.toLowerCase().contains(q) || m.employeeId.contains(q);
        }).toList()..sort((a,b) => a.name.compareTo(b.name));
        return ListView(padding: const EdgeInsets.all(14), children: [
          const Text('Manager team • View officers or filter permitted performance',
            style: TextStyle(color: Palette.muted)),
          const SizedBox(height: 10),
          TextField(controller: search, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Search manager name or branch',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.clear),
                onPressed: () { search.clear(); setState(() {}); }))),
          const SizedBox(height: 10),
          Text('${filtered.length} Managers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (filtered.isEmpty) const SectionCard(child: Text('No matching managers.')),
          for (final manager in filtered) Builder(builder: (context) {
            final officers = allPeople.where((e) => e.isOfficer &&
              ApiClient.isDirectoryApproved(e.status) && belongsToManager(e, manager)).toList();
            final teamIds = officers.map((e) => e.employeeId).toSet();
            final teamRecords = reports.where((r) => teamIds.contains(r.employeeId)
              && r.managerId == manager.employeeId).toList();
            final legacyUnlinked = officers.where((e) =>
              e.managerId.isEmpty && belongsToManager(e, manager)).length;
            final branches = officers.map((e) => e.displayBranch).toSet().join(', ');
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.supervisor_account_outlined)),
              title: Text(manager.name),
              subtitle: Text('${officers.length} Officers • ${countCards(teamRecords)} Cards'
                '${branches.isEmpty ? '' : '\n$branches'}'
                '${legacyUnlinked > 0 ? '\n$legacyUnlinked officer(s) need Manager ID linking' : ''}'),
              isThreeLine: branches.isNotEmpty,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _choose(manager, officers),
            ));
          }),
        ]);
      }),
  );
}

class _TeamOfficers extends StatelessWidget {
  const _TeamOfficers({required this.session, required this.manager, required this.officers});
  final Session session;
  final Employee manager;
  final List<Employee> officers;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Team: ${manager.name}')),
    body: ListView(children: [
      Padding(padding: const EdgeInsets.all(16),
        child: Text('${officers.length} approved officers')),
      for (final e in officers) ListTile(
        leading: EmployeeAvatar(employee: e),
        title: Text(e.name),
        subtitle: Text('${e.employeeId} • ${e.displayBranch} • ${e.displayZone}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
          EmployeeProfileScreen(session: session, id: e.employeeId))),
      ),
    ]),
  );
}

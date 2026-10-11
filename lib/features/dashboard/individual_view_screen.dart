import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/entities.dart';
import '../../services/calculations.dart';
import '../../services/report_scope.dart';
import '../../services/session.dart';
import '../employees/directory_screen.dart';
import '../performance/my_reports_screen.dart';

/// Private officer report directory for management. This is deliberately NOT
/// the public Employee Directory used by Officer List and Ranking.
class IndividualViewScreen extends StatefulWidget {
  const IndividualViewScreen({super.key, required this.session});
  final Session session;

  @override
  State<IndividualViewScreen> createState() => _IndividualViewScreenState();
}

class _IndividualViewScreenState extends State<IndividualViewScreen> {
  final search = TextEditingController();
  late Future<List<Employee>> officers;
  StreamSubscription<List<Employee>>? updates;

  void load() {
    officers = widget.session.api.employees().then((people) =>
        permittedReportOfficers(widget.session.user!, people));
  }

  @override
  void initState() {
    super.initState();
    load();
    updates = widget.session.api.watchDirectory().listen((_) {
      if (mounted) { setState(load); }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    updates?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Individual View'),
      actions: [IconButton(onPressed: () => setState(load),
          tooltip: 'Refresh', icon: const Icon(Icons.refresh))],
    ),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Search officer, ID, branch or zone',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ),
      Expanded(child: FutureBuilder<List<Employee>>(
        future: officers,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return LoadError(message: '${snapshot.error}',
                retry: () => setState(load));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final q = search.text.trim().toLowerCase();
          final results = snapshot.data!.where((e) => [
            e.name, e.employeeId, e.branch, e.zone,
          ].any((value) => value.toLowerCase().contains(q))).toList();
          return ListView(padding: const EdgeInsets.all(12), children: [
            Padding(padding: const EdgeInsets.all(8),
              child: Text('${results.length} officers • Select to view monthly performance',
                  style: const TextStyle(color: Palette.muted))),
            if (results.isEmpty) const Padding(
                padding: EdgeInsets.all(24), child: Text('No permitted officers found.')),
            for (final officer in results)
              Card(child: ListTile(
                leading: EmployeeAvatar(employee: officer),
                title: Text(officer.name),
                subtitle: Text('${officer.employeeId} • ${officer.displayBranch} • ${officer.displayZone}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => _OfficerMonthlyReports(
                        session: widget.session, officer: officer))),
              )),
          ]);
        },
      )),
    ]),
  );
}

class _OfficerMonthlyReports extends StatefulWidget {
  const _OfficerMonthlyReports({required this.session, required this.officer});
  final Session session;
  final Employee officer;
  @override
  State<_OfficerMonthlyReports> createState() => _OfficerMonthlyReportsState();
}

class _OfficerMonthlyReportsState extends State<_OfficerMonthlyReports> {
  late Future<List<CardRecord>> reports;
  StreamSubscription<Map<String, int>>? updates;

  void reload() {
    reports = widget.session.api.records(employeeId: widget.officer.employeeId);
  }

  @override
  void initState() {
    super.initState();
    reload();
    updates = widget.session.api.watchRankingCounts().listen((_) {
      if (mounted) setState(reload);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    updates?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.officer.name,
        maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(onPressed: () => setState(reload),
            icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<CardRecord>>(
      future: reports,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return LoadError(message: '${snapshot.error}', retry: () => setState(reload));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = <String, List<CardRecord>>{};
        for (final record in snapshot.data!) {
          if (record.status == 'deleted') { continue; }
          (groups[record.reportingPeriod] ??= []).add(record);
        }
        final periods = groups.keys.toList()..sort((a, b) => b.compareTo(a));
        if (periods.isEmpty) {
          return const Center(child: Text('No submitted performance reports.'));
        }
        return ListView(padding: const EdgeInsets.all(12), children: [
          Padding(padding: const EdgeInsets.all(8), child: Text(
            '${widget.officer.employeeId} • ${widget.officer.displayBranch}',
            style: const TextStyle(color: Palette.muted))),
          for (final period in periods)
            Card(child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined,
                  color: Palette.primary),
              title: Text(readablePeriod(period)),
              subtitle: Text('${countCards(groups[period]!)} 906 cards • Submitted'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ReportDetailScreen(
                    session: widget.session, items: groups[period]!),
              )),
            )),
        ]);
      },
    ),
  );
}

import '../../core/report_years.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/entities.dart';
import '../../services/calculations.dart';
import '../../services/session.dart';
import '../performance/my_reports_screen.dart';

/// Management Month View. Uses the SAME card-count service as Ranking/Reports
/// and respects backend-enforced scope when retrieving performance documents.
class MonthViewScreen extends StatefulWidget {
  const MonthViewScreen({super.key, required this.session, this.managerId, this.managerName});
  final Session session;
  final String? managerId, managerName;

  @override
  State<MonthViewScreen> createState() => _MonthViewScreenState();
}

class _MonthViewScreenState extends State<MonthViewScreen> {
  late Future<_Data> future;
  final search = TextEditingController();
  int year = DateTime.now().year;
  int month = 0; // 0 => All Months
  String branch = 'All branches';
  String zone = 'All zones';

  @override
  void initState() {
    super.initState();
    reload();
    _updates=widget.session.api.watchRankingCounts().listen((_) => _liveRefresh(), onError: (_) {});
  }
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
    search.dispose();
    super.dispose();
  }

  void reload() {
    future = _getData();
  }

  Future<_Data> _getData() async {
    final records = await widget.session.api.records();
    final employees = await widget.session.api.employees();
    return _Data(records, employees);
  }


  List<CardRecord> _activeRecords(_Data data, {bool applyMonth = true}) {
    final text = search.text.trim().toLowerCase();
    final employeesById = {
      for (final employee in data.employees) employee.employeeId: employee,
    };
    return data.records.where((record) {
      if (record.status == 'deleted') return false;
      if (widget.managerId != null && record.managerId != widget.managerId &&
          !(record.managerId.isEmpty && record.salesManager.trim().toLowerCase() ==
              (widget.managerName ?? '').trim().toLowerCase())) {
        return false;
      }
      if (record.reportingPeriod.length < 7 ||
          int.tryParse(record.reportingPeriod.substring(0, 4)) != year) {
        return false;
      }
      if (applyMonth && month != 0 &&
          int.tryParse(record.reportingPeriod.substring(5, 7)) != month) {
        return false;
      }
      final employee = employeesById[record.employeeId];
      final employeeBranch = upper(record.branch.isNotEmpty
          ? record.branch : (employee?.branch ?? ''));
      final employeeZone = upper(record.zone.isNotEmpty
          ? record.zone : (employee?.zone ?? ''));
      if (branch != 'All branches' && employeeBranch != branch) return false;
      if (zone != 'All zones' && employeeZone != zone) return false;
      return text.isEmpty || [
        record.employeeName, record.employeeId, record.applicantName,
        employee?.name ?? '', employeeBranch, employeeZone,
      ].any((value) => value.toLowerCase().contains(text));
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Month View'),
      actions: [IconButton(
        tooltip: 'Refresh reports',
        onPressed: () => setState(reload),
        icon: const Icon(Icons.refresh_rounded),
      )],
    ),
    body: FutureBuilder<_Data>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return LoadError(
            message: '${snapshot.error}',
            retry: () => setState(reload),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final selected = _activeRecords(data);
        final trendRecords = _activeRecords(data, applyMonth: false);
        final years = <int>{...reportYears, DateTime.now().year, year,
          ...data.records.map((r) => int.tryParse(
            r.reportingPeriod.length >= 4
                ? r.reportingPeriod.substring(0, 4) : '') ?? year),
        }.toList()..sort((a, b) => b.compareTo(a));
        final branches = <String>{
          'All branches',
          ...data.employees.map((e) => upper(e.branch)).where((x) => x.isNotEmpty),
          ...data.records.map((r) => upper(r.branch)).where((x) => x.isNotEmpty),
        }.toList()..sort();
        final zones = <String>{
          'All zones',
          ...data.employees.map((e) => upper(e.zone)).where((x) => x.isNotEmpty),
          ...data.records.map((r) => upper(r.zone)).where((x) => x.isNotEmpty),
        }.toList()..sort();
        final totals = countCards(selected);
        final reportGroups = <String, List<CardRecord>>{};
        for (final record in selected) {
          (reportGroups['${record.reportingPeriod}|${record.employeeId}'] ??= [])
              .add(record);
        }
        final keys = reportGroups.keys.toList()
          ..sort((a, b) {
            final byMonth = b.substring(0, 7).compareTo(a.substring(0, 7));
            return byMonth != 0 ? byMonth : a.compareTo(b);
          });
        final employees = selected.map((r) => r.employeeId).toSet().length;
        final nils = reportGroups.values.where((group) =>
          group.any((r) => r.isNil) && countCards(group) == 0).length;
        final byMonth = <int, int>{
          for (var m = 1; m <= 12; m++) m: countCards(trendRecords,
            reportingPeriod: '$year-${m.toString().padLeft(2, '0')}'),
        };
        final maxCards = math.max(1, byMonth.values.fold<int>(0, math.max));

        return RefreshIndicator(
          onRefresh: () async {
            setState(reload);
            await future;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Performance overview',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold, color: Palette.dark)),
                  const SizedBox(height: 4),
                  const Text('Review verified cards, team submissions and trends.',
                    style: TextStyle(color: Palette.muted)),
                  const SizedBox(height: 16),
                  SectionCard(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('REPORT FILTERS', style: TextStyle(
                        fontWeight: FontWeight.bold, color: Palette.primary)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        SizedBox(width: 155, child: DropdownButtonFormField<int>(
                          key: ValueKey('year_$year'), initialValue: year,
                          decoration: const InputDecoration(labelText: 'Year',
                            prefixIcon: Icon(Icons.event)),
                          items: [for (final value in years) DropdownMenuItem(
                            value: value, child: Text('$value'))],
                          onChanged: (v) => setState(() => year = v ?? year),
                        )),
                        SizedBox(width: 195, child: DropdownButtonFormField<int>(
                          key: ValueKey('month_$month'), initialValue: month,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Month',
                            prefixIcon: Icon(Icons.calendar_month_outlined)),
                          items: [const DropdownMenuItem(value: 0,
                            child: Text('All months')),
                            for (var i = 0; i < monthNames.length; i++)
                              DropdownMenuItem(value: i + 1,
                                child: Text(monthNames[i]))],
                          onChanged: (v) => setState(() => month = v ?? 0),
                        )),
                        SizedBox(width: 190, child: DropdownButtonFormField<String>(
                          key: ValueKey('branch_$branch'),
                          isExpanded: true, initialValue: branches.contains(branch)
                              ? branch : 'All branches',
                          decoration: const InputDecoration(labelText: 'Branch'),
                          items: [for (final value in branches) DropdownMenuItem(
                            value: value, child: Text(value,
                            maxLines: 1, overflow: TextOverflow.ellipsis))],
                          onChanged: (v) => setState(() => branch = v ?? 'All branches'),
                        )),
                        SizedBox(width: 190, child: DropdownButtonFormField<String>(
                          key: ValueKey('zone_$zone'),
                          isExpanded: true, initialValue: zones.contains(zone)
                              ? zone : 'All zones',
                          decoration: const InputDecoration(labelText: 'Zone'),
                          items: [for (final value in zones) DropdownMenuItem(
                            value: value, child: Text(value,
                            maxLines: 1, overflow: TextOverflow.ellipsis))],
                          onChanged: (v) => setState(() => zone = v ?? 'All zones'),
                        )),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                        controller: search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search employee, ID, applicant, branch or zone',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'Clear search',
                            onPressed: () { search.clear(); setState(() {}); },
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ],
                  )),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, size) {
                    final compact = size.maxWidth < 650;
                    return Wrap(spacing: 10, runSpacing: 10, children: [
                      _stat('906 cards', '$totals', Icons.credit_card,
                          compact ? (size.maxWidth - 10) / 2 : (size.maxWidth - 30) / 4),
                      _stat('Report groups', '${keys.length}', Icons.description_outlined,
                          compact ? (size.maxWidth - 10) / 2 : (size.maxWidth - 30) / 4),
                      _stat('Employees', '$employees', Icons.groups_outlined,
                          compact ? (size.maxWidth - 10) / 2 : (size.maxWidth - 30) / 4),
                      _stat('NIL submitted', '$nils', Icons.fact_check_outlined,
                          compact ? (size.maxWidth - 10) / 2 : (size.maxWidth - 30) / 4),
                    ]);
                  }),
                  const SizedBox(height: 12),
                  SectionCard(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Monthly card trend • $year', style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('Unique valid accounts (NIL and duplicates excluded)',
                        style: TextStyle(color: Palette.muted, fontSize: 12)),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end,
                          children: [for (var m = 1; m <= 12; m++)
                            Padding(padding: const EdgeInsets.only(right: 9),
                              child: InkWell(
                                onTap: () => setState(() => month = m),
                                child: SizedBox(width: 55,
                                  child: Column(children: [
                                    Text('${byMonth[m]}', style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 12)),
                                    const SizedBox(height: 5),
                                    Container(
                                      height: 20 + 90 * (byMonth[m]! / maxCards),
                                      decoration: BoxDecoration(
                                        color: month == m ? Palette.primary : Palette.pale,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(monthNames[m - 1].substring(0, 3),
                                        style: const TextStyle(fontSize: 12)),
                                  ]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Expanded(child: Text('MONTHLY REPORTS', style: TextStyle(
                      color: Palette.dark, fontWeight: FontWeight.bold))),
                    Text('${keys.length} groups',
                        style: const TextStyle(color: Palette.muted)),
                  ]),
                  const SizedBox(height: 8),
                  if (keys.isEmpty) SectionCard(child: const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('No reports match these filters.')),
                  )),
                  for (final key in keys)
                    _reportCard(context, reportGroups[key]!),
                ],
              ),
            )),
          ]),
        );
      },
    ),
  );

  Widget _stat(String title, String value, IconData icon, double width) =>
    SizedBox(width: width, child: SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Palette.primary),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 25,
            fontWeight: FontWeight.bold)),
        Text(title, maxLines: 2, style: const TextStyle(color: Palette.muted)),
      ],
    )));

  Widget _reportCard(BuildContext context, List<CardRecord> records) {
    final first = records.first;
    final valid = countCards(records);
    final nil = valid == 0 && records.any((r) => r.isNil);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: Palette.pale,
          child: Text('$valid', style: const TextStyle(
            fontWeight: FontWeight.bold, color: Palette.primary)),
        ),
        title: Text(first.employeeName.isNotEmpty
            ? first.employeeName : first.employeeId,
          style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${readablePeriod(first.reportingPeriod)} • '
            '${upper(first.branch)}\n'
            '${first.employeeId} • ${nil ? 'NIL submitted' : '$valid 906 card(s)'}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => ReportDetailScreen(session: widget.session,
              items: records),
          ));
          if (mounted) setState(reload);
        },
      ),
    );
  }
}

class _Data {
  const _Data(this.records, this.employees);
  final List<CardRecord> records;
  final List<Employee> employees;
}

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/entities.dart';
import '../../services/api.dart';
import '../../services/session.dart';
import '../employees/directory_screen.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key, required this.session});
  final Session session;
  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  final search = TextEditingController();
  late Stream<List<Employee>> people;
  late Stream<Map<String,int>> scores;
  @override
  void initState() {super.initState(); scores=widget.session.api.watchRankingCounts(); _reload();}
  void _reload() { people = widget.session.api.watchDirectory(); }
  @override
  void dispose() {search.dispose(); super.dispose();}

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Performance Leaderboard'),
      actions: [IconButton(tooltip: 'Refresh officers', icon: const Icon(Icons.refresh),
        onPressed: () => setState(_reload))]),
    body: StreamBuilder<List<Employee>>(stream: people, builder: (context, employees) {
      if (employees.hasError) {
        return LoadError(message: '${employees.error}',
          retry: () => setState(_reload));
      }
      if (!employees.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return StreamBuilder<Map<String,int>>(
        stream: scores,
        builder: (context, countsSnap) {
          if (countsSnap.hasError) {
            return LoadError(message: '${countsSnap.error}',
              retry: () => setState(_reload));
          }
          if (!countsSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final counts = countsSnap.data!;
          // Show EVERY approved officer, even when cards = 0, regardless
          // of whether a published ranking document existed previously.
          final officers = employees.data!.where((e) => e.isOfficer &&
            ApiClient.isDirectoryApproved(e.status)).toList()
            ..sort((a,b) {
              final cmp = (counts[b.employeeId] ?? 0).compareTo(counts[a.employeeId] ?? 0);
              if (cmp != 0) { return cmp; }
              final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
              return name == 0 ? a.employeeId.compareTo(b.employeeId) : name;
            });
          final rows = <RankingEntry>[
            for (var i=0; i<officers.length; i++)
              RankingEntry(officers[i], counts[officers[i].employeeId] ?? 0, i+1),
          ];
          final q = search.text.trim().toLowerCase();
          final visible = rows.where((r) => [r.employee.name, r.employee.employeeId,
            r.employee.branch, r.employee.zone].any((v) => v.toLowerCase().contains(q))).toList();
          final mine = rows.where((r) => r.employee.employeeId ==
            widget.session.user!.employeeId).firstOrNull;
          return ListView(padding: const EdgeInsets.all(12), children: [
            Text('${rows.length} approved officers • Live Ranking',
              style: const TextStyle(color: Palette.muted)),
            const SizedBox(height: 12),
            if (mine != null) SectionCard(child: Text(
              'Your Current Position: #${mine.rank} • ${mine.cards} cards',
              style: const TextStyle(fontWeight: FontWeight.bold))),
            if (rows.isNotEmpty) SectionCard(child: Column(children: [
              const Text('TOP PERFORMERS', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end, children: [
                for(final i in [1,0,2]) if (i < rows.length) Expanded(child: Column(children: [
                  Icon(i==0 ? Icons.workspace_premium : Icons.emoji_events,
                    color: i==0 ? Colors.amber : i==1 ? Colors.blueGrey : Colors.brown),
                  EmployeeAvatar(employee: rows[i].employee, radius: i==0?33:26),
                  Text(rows[i].employee.name, maxLines: 2, textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis),
                  Text('#${i+1} • ${rows[i].cards}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ])),
              ]),
            ])),
            TextField(controller: search, onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Search name, ID, branch, zone',
                prefixIcon: Icon(Icons.search))),
            const SizedBox(height: 12),
            if (visible.isEmpty) const Text('No matching officers'),
            for (final r in visible) Card(child: ListTile(
              leading: EmployeeAvatar(employee: r.employee),
              title: Text('#${r.rank}  ${r.employee.name}'),
              subtitle: Text('${r.employee.employeeId} • '
                '${r.employee.displayBranch} • ${r.employee.displayZone}'),
              trailing: Text('${r.cards} cards',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Palette.primary)),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
                EmployeeProfileScreen(session: widget.session, id: r.employee.employeeId))),
            )),
            const SizedBox(height: 12),
            const Text('Counts update automatically after confirmed submissions. '
              'Pre-existing cards require a one-time protected migration '
              'before their historical totals appear.',
              style: TextStyle(color: Palette.muted)),
          ]);
        },
      );
    }),
  );
}

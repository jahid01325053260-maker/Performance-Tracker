import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/report_years.dart';
import '../../models/entities.dart';
import '../../services/kpi_pdf_parser.dart';
import '../../services/session.dart';
import '../auth/login_screen.dart';

class SubmissionScreen extends StatefulWidget {
  const SubmissionScreen({super.key, required this.session});
  final Session session;
  @override
  State<SubmissionScreen> createState() => _SubmissionScreenState();
}

class _EntryRow {
  final name = TextEditingController();
  final account = TextEditingController();
  final limit = TextEditingController();
  void dispose() {
    name.dispose();
    account.dispose();
    limit.dispose();
  }
}

class _SubmissionScreenState extends State<SubmissionScreen> {
  final rows = <_EntryRow>[_EntryRow()];
  int month = DateTime.now().month;
  int year = DateTime.now().year;
  bool nil = false;
  bool busy = false;

  @override
  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> addPdf() async {
    setState(() => busy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'],
      );
      if (files.isEmpty) { return; }
      final file = files.single;
      if (await file.length() > 20 * 1024 * 1024) {
        throw const FormatException('PDF must be smaller than 20 MB.');
      }
      final result = await KpiPdfParser.parseBytes(await file.readAsBytes());
      if (!mounted) { return; }
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) =>
        PdfReviewScreen(session: widget.session, result: result)));
    } catch (error) {
      if (mounted) { showMessage(context, 'PDF Import failed: $error'); }
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  Future<void> submit() async {
    if (nil && rows.any((r) =>
      r.name.text.trim().isNotEmpty || r.account.text.trim().isNotEmpty)) {
      showMessage(context, 'Remove filled rows before marking zero approval');
      return;
    }
    if (!nil && rows.any((r) => r.name.text.trim().isEmpty ||
      !RegExp(r'^\d{4}-?906-?\d{6}$').hasMatch(r.account.text.trim()) ||
      r.limit.text.trim().isEmpty)) {
      showMessage(context,
        'Enter applicant, a valid 906 account (####-906-######), and limit in each row');
      return;
    }
    final period = '$year-${month.toString().padLeft(2, '0')}';
    setState(() => busy = true);
    try {
      await widget.session.api.submit(period, [
        for (final r in rows)
          if (!nil) {
            'applicantName': r.name.text.trim(),
            'accountNo': r.account.text.trim(),
            'limit': r.limit.text.trim(),
          },
      ], nil: nil);
      if (!mounted) { return; }
      showMessage(context, 'Submission saved');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) { showMessage(context, '$e'); }
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New Submission')),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: ListView(padding: const EdgeInsets.all(14), children: [
        SectionCard(child: Row(children: [
          Expanded(child: DropdownButtonFormField<int>(
            initialValue: month,
            decoration: const InputDecoration(labelText: 'Reporting Month'),
            items: [for (var i = 1; i <= 12; i++)
              DropdownMenuItem(value: i, child: Text(monthNames[i - 1]))],
            onChanged: (v) => setState(() => month = v ?? month),
          )),
          const SizedBox(width: 12),
          SizedBox(width: 120, child: TextFormField(
            initialValue: '$year',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Year'),
            onChanged: (v) {
              final y = int.tryParse(v);
              if (y != null && y >= firstReportYear && y <= lastReportYear) { year = y; }
            },
          )),
        ])),
        CheckboxListTile(
          value: nil,
          onChanged: busy ? null : (v) => setState(() => nil = v ?? false),
          title: const Text('Zero approval this month'),
          subtitle: const Text('Records NIL status; counts zero cards'),
        ),
        if (!nil)
          for (var i = 0; i < rows.length; i++)
            SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text('APPLICATION ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (rows.length > 1) IconButton(
                    tooltip: 'Remove row',
                    onPressed: () => setState(() => rows.removeAt(i).dispose()),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ]),
                TextField(controller: rows[i].name,
                  decoration: const InputDecoration(labelText: 'Applicant Name')),
                const SizedBox(height: 10),
                TextField(controller: rows[i].account,
                  decoration: const InputDecoration(labelText: 'A/C No (####-906-######)')),
                const SizedBox(height: 10),
                TextField(controller: rows[i].limit,
                  decoration: const InputDecoration(labelText: 'Limit (amount)')),
              ],
            )),
        if (!nil) OutlinedButton.icon(
          onPressed: busy ? null : () => setState(() => rows.add(_EntryRow())),
          icon: const Icon(Icons.add), label: const Text('Add More Row')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: busy ? null : addPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(busy ? 'Reading PDF...' : 'Import Multi-Month KPI PDF')),
        const SizedBox(height: 6),
        const Text('PDF Import detects SL, Account No, Account Title, Amount and Period. '
          'Only 906 accounts are counted. Months are assigned from the Period column.',
          textAlign: TextAlign.center, style: TextStyle(color: Palette.muted)),
        const SizedBox(height: 14),
        FilledButton(onPressed: busy ? null : submit,
          child: Text(busy ? 'Processing...' : 'Submit')),
      ]),
    )),
  );
}

class PdfReviewScreen extends StatefulWidget {
  const PdfReviewScreen({super.key, required this.session, required this.result});
  final Session session;
  final KpiPdfResult result;
  @override
  State<PdfReviewScreen> createState() => _PdfReviewScreenState();
}

class _PdfReviewScreenState extends State<PdfReviewScreen> {
  late final List<Map<String, dynamic>> rows;
  bool busy = false;
  int processed = 0;

  @override
  void initState() {
    super.initState();
    rows = widget.result.rows.map((e) => e.toSubmission()).toList();
  }

  Map<String, int> get monthly {
    final result = <String, int>{};
    for (final row in rows) {
      final period = '${row['reportingPeriod']}';
      result.update(period, (n) => n + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(result.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key)));
  }

  Future<void> submitAll() async {
    if (rows.isEmpty) { return; }
    final confirm = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(title: const Text('Confirm PDF Import'),
        content: Text('Save ${rows.length} selected 906 accounts now? '
          'After confirmation an officer cannot edit or delete submitted reports.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('CONFIRM & UPLOAD'))]));
    if (confirm != true || !mounted) return;
    final grouped = <String, List<Map<String, dynamic>>>{};
    final seen = <String>{};
    for (final row in rows) {
      final period = '${row['reportingPeriod'] ?? ''}';
      final account = '${row['accountNo'] ?? ''}'.trim();
      final title = '${row['applicantName'] ?? ''}'.trim();
      if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period) ||
        !RegExp(r'^\d{4}-906-\d{6}$').hasMatch(account) || title.isEmpty) {
        showMessage(context, 'Check month, 906 account number and account title before saving.');
        return;
      }
      if (!seen.add('$period|$account')) {
        showMessage(context, 'Duplicate $account within $period. Remove duplicates.');
        return;
      }
      (grouped[period] ??= []).add(row);
    }
    setState(() { busy = true; processed = 0; });
    try {
      for (final entry in grouped.entries) {
        await widget.session.api.submit(entry.key, entry.value);
        if (mounted) { setState(() => processed += entry.value.length); }
      }
      if (!mounted) { return; }
      showMessage(context,
        'Processed $processed 906 account(s) across ${grouped.length} month(s). '
        'Existing submissions were not duplicated.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        showMessage(context,
          '$processed records processed before an error: $error. '
          'Check My Reports before retrying; existing accounts will not be duplicated.');
      }
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = monthly;
    return Scaffold(
      appBar: AppBar(title: const Text('Review PDF KPI Import')),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(padding: const EdgeInsets.all(14), children: [
          SectionCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PDF Import Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(label: Text('Total PDF: ${widget.result.total}')),
                Chip(label: Text('906 selected: ${rows.length}')),
                Chip(label: Text('Non-906: ${widget.result.non906}')),
                if (widget.result.duplicate > 0)
                  Chip(label: Text('Duplicate: ${widget.result.duplicate}')),
                if (widget.result.issues.isNotEmpty)
                  Chip(label: Text('Need review: ${widget.result.issues.length}')),
              ]),
              const Text('The reporting month is taken from the PDF Period column, '
                'not Maker Date or the month chosen on New Submission.'),
              const SizedBox(height: 8),
              const Text('Verify Y and N are both included because only product '
                'code 906 is filtered. Empty Amount does not remove a card.',
                style: TextStyle(color: Palette.muted)),
            ],
          )),
          const SizedBox(height: 10),
          SectionCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Automatic Month Allocation',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              for (final group in counts.entries) Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text(readablePeriod(group.key))),
                  Text('${group.value} account(s)',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ),
            ],
          )),
          if (widget.result.issues.isNotEmpty) SectionCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Records not ready to import',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              for (final issue in widget.result.issues)
                Text('SL ${issue.serial}: ${issue.message}'),
            ],
          )),
          const SizedBox(height: 10),
          Text('Review ${rows.length} accounts before submitting',
            style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < rows.length; i++)
            Card(key: ValueKey('${rows[i]['slNo']}-${rows[i]['accountNo']}'),
              child: ExpansionTile(
                title: Text('SL ${rows[i]['slNo']}  •  ${rows[i]['accountNo']}'),
                subtitle: Text('${rows[i]['applicantName']}  •  ${readablePeriod('${rows[i]['reportingPeriod']}')}'),
                trailing: Text('${rows[i]['limit'] == '' ? 'N/A' : rows[i]['limit']}'),
                childrenPadding: const EdgeInsets.all(12),
                children: [
                  TextFormField(initialValue: '${rows[i]['applicantName']}',
                    decoration: const InputDecoration(labelText: 'Account Title'),
                    onChanged: (v) => rows[i]['applicantName'] = v.trim()),
                  const SizedBox(height: 8),
                  TextFormField(initialValue: '${rows[i]['accountNo']}',
                    decoration: const InputDecoration(labelText: 'Account No (906)'),
                    onChanged: (v) => rows[i]['accountNo'] = v.trim()),
                  const SizedBox(height: 8),
                  TextFormField(initialValue: '${rows[i]['limit']}',
                    decoration: const InputDecoration(labelText: 'Achievement Amount (optional)'),
                    onChanged: (v) => rows[i]['limit'] = v.trim()),
                  const SizedBox(height: 8),
                  Text('Period: ${rows[i]['periodStart']} to ${rows[i]['periodEnd']} '
                    '→ ${readablePeriod('${rows[i]['reportingPeriod']}')}'),
                  Text('Verify: ${rows[i]['verify']?.toString().isEmpty == true ? 'Unknown' : rows[i]['verify']} '
                    '• Branch: ${rows[i]['originatingBranch']}'),
                  Align(alignment: Alignment.centerRight,
                    child: TextButton.icon(onPressed: busy ? null : () => setState(() => rows.removeAt(i)),
                      icon: const Icon(Icons.delete_outline), label: const Text('Exclude row'))),
                ],
              )),
          const SizedBox(height: 16),
          if (busy) LinearProgressIndicator(value: rows.isEmpty ? 0 : processed / rows.length),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: busy || rows.isEmpty ? null : submitAll,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(busy ? 'Uploading $processed/${rows.length}...' :
              'Submit all ${rows.length} accounts to their months')),
          const SizedBox(height: 12),
          const Text('This import uses the live online database. '
            'For safety, existing account IDs are not counted twice.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted)),
        ]),
      )),
    );
  }
}

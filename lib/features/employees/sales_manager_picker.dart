import 'package:flutter/material.dart';
import '../../models/entities.dart';
import '../../services/api.dart';

/// Uses a name-and-ID-only Firestore catalog so registration can select a
/// manager BEFORE Firebase Authentication; no private employee data is exposed.
class SalesManagerPicker extends StatefulWidget {
  const SalesManagerPicker({super.key, required this.api, required this.onChanged,
    this.initialManagerId = '', this.required = true, this.enabled = true});
  final ApiClient api;
  final String initialManagerId;
  final ValueChanged<SalesManagerOption?> onChanged;
  final bool required, enabled;
  @override
  State<SalesManagerPicker> createState() => _SalesManagerPickerState();
}

class _SalesManagerPickerState extends State<SalesManagerPicker> {
  late Future<List<SalesManagerOption>> managers;
  String? selected;
  @override
  void initState() {
    super.initState();
    selected = widget.initialManagerId.isEmpty ? null : widget.initialManagerId;
    managers = widget.api.salesManagers();
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<List<SalesManagerOption>>(
    future: managers,
    builder: (context, snap) {
      if (snap.hasError) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Sales Manager list unavailable: ${snap.error}'),
          TextButton(onPressed: () => setState(() => managers = widget.api.salesManagers()),
            child: const Text('RETRY')),
        ]);
      }
      if (!snap.hasData) return const LinearProgressIndicator();
      final all = snap.data!;
      final current = all.any((m) => m.employeeId == selected) ? selected : null;
      return DropdownButtonFormField<String>(
        key: ValueKey('sales_managers_${all.length}_$current'),
        initialValue: current,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Sales Manager',
          helperText: 'Choose an approved Sales Manager'),
        items: [
          if (!widget.required) const DropdownMenuItem(value: '', child: Text('No manager')),
          for (final manager in all) DropdownMenuItem(
            value: manager.employeeId,
            child: Text('${manager.name} (${manager.employeeId})',
              overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: widget.enabled ? (value) {
          selected = value;
          final matching = all.where((m) => m.employeeId == value).toList();
          widget.onChanged(matching.isEmpty ? null : matching.single);
        } : null,
        validator: widget.required
          ? (_) => all.isEmpty
            ? 'Admin must publish the approved Sales Manager list'
            : current == null ? 'Select a Sales Manager from the list' : null
          : null,
      );
    },
  );
}

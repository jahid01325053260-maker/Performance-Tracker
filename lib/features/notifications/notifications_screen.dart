import 'package:flutter/material.dart';
import '../../services/session.dart';
import '../../services/notification_service.dart';
import '../../core/theme.dart';
import '../auth/login_screen.dart' show showMessage;

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications'), actions: [
      IconButton(tooltip: 'Notification permission',
        icon: const Icon(Icons.notifications_active_outlined),
        onPressed: () async {
          final allowed = await DeviceAlerts.requestPermission();
          if (context.mounted) {
            showMessage(context, allowed
              ? 'Device notifications enabled.'
              : 'Device notifications not enabled. Alerts still appear in this inbox.');
          }
        }),
    ]),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: session.api.watchOwnAlerts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Unable to read alerts: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final alerts = snapshot.data!;
        if (alerts.isEmpty) return const Center(child: Text('No alerts yet.'));
        return ListView.separated(padding: const EdgeInsets.all(12),
          itemCount: alerts.length, separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final alert = alerts[index];
            return Card(child: ListTile(
              leading: const Icon(Icons.notifications_outlined, color: Palette.primary),
              title: Text('${alert['title'] ?? 'Report alert'}'),
              subtitle: Text('${alert['body'] ?? ''}'),
            ));
          },
        );
      },
    ),
  );
}

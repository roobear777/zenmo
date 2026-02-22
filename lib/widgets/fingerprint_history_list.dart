// lib/widgets/fingerprint_history_list.dart
import 'package:flutter/material.dart';
import '../fingerprint_repo.dart';

class FingerprintHistoryList extends StatelessWidget {
  const FingerprintHistoryList({super.key, this.limit = 24});

  final int limit;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FingerprintRepo.historyStream(limit: limit),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error loading history: ${snap.error}'),
          );
        }
        final items = snap.data ?? const [];

        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No fingerprint history yet.'),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final m = items[i];
            final String monthId = (m['monthId'] as String?) ?? 'Unknown';
            final DateTime? createdAt = m['createdAt'] as DateTime?;
            final int total = (m['total'] is int) ? m['total'] as int : 0;

            final subtitle =
                createdAt != null
                    ? 'Saved: ${createdAt.toLocal()}'
                    : 'Saved: unknown time';

            return ListTile(
              leading: const Icon(Icons.fingerprint),
              title: Text('Fingerprint $monthId'),
              // FIX: replace mojibake with a proper bullet.
              subtitle: Text(
                '$subtitle • $total color${total == 1 ? '' : 's'}',
              ),
              dense: true,
              onTap: () {
                // Optional: navigate to a detail screen later.
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Fingerprint $monthId')));
              },
            );
          },
        );
      },
    );
  }
}

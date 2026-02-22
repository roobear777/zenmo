// lib/admin/admin_party_results_tab.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:color_wallet/fingerprint_grid.dart';

class AdminPartyResultsTab extends StatelessWidget {
  const AdminPartyResultsTab({
    super.key,
    required this.db,
    this.eventKey = 'party',
  });

  final FirebaseFirestore db;
  final String eventKey;

  static final List<int> _spiral5x5 = _centerOutSpiral(rows: 5, cols: 5);

  @override
  Widget build(BuildContext context) {
    final query = db
        .collection('events')
        .doc(eventKey)
        .collection('fingerprints')
        .orderBy('updatedAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('No party fingerprints yet.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = d.data();
            final uid = (data['uid'] is String) ? data['uid'] as String : d.id;

            final raw = data['answers'];
            final List<Map<String, dynamic>> answers = <Map<String, dynamic>>[];
            if (raw is List) {
              for (final e in raw) {
                if (e is Map) answers.add(Map<String, dynamic>.from(e));
              }
            }

            final colors = <int>[];
            for (final m in answers) {
              final v = m['colorInt'];
              if (v is int) colors.add(v);
              if (v is num) colors.add(v.toInt());
            }

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFE6E8ED)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uid,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 220,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: FingerprintGrid(
                          answers: colors,
                          total: 25,
                          borderColor: Colors.transparent,
                          borderWidth: 0,
                          cornerRadius: 8,
                          gap: 0,
                          forceCols: 5,
                          placementOrder: _spiral5x5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Party grid',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...answers.asMap().entries.map((e) {
                      final idx = e.key;
                      final m = e.value;
                      final int c =
                          (m['colorInt'] is int)
                              ? m['colorInt'] as int
                              : (m['colorInt'] is num)
                              ? (m['colorInt'] as num).toInt()
                              : 0xFF000000;
                      final String title =
                          (m['title'] is String) ? (m['title'] as String) : '';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Color(c),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.black12),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${idx + 1}. $title')),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static List<int> _centerOutSpiral({required int rows, required int cols}) {
    final total = rows * cols;
    final List<int> order = [];
    int r = rows ~/ 2, c = cols ~/ 2;
    order.add(r * cols + c);

    int step = 1;
    final dirs = <List<int>>[
      [1, 0],
      [0, 1],
      [-1, 0],
      [0, -1],
    ];
    int d = 0;

    while (order.length < total) {
      for (int rep = 0; rep < 2; rep++) {
        final dx = dirs[d % 4][0];
        final dy = dirs[d % 4][1];
        for (int s = 0; s < step; s++) {
          c += dx;
          r += dy;
          if (r >= 0 && r < rows && c >= 0 && c < cols) {
            order.add(r * cols + c);
            if (order.length == total) return order;
          }
        }
        d++;
      }
      step++;
    }
    return order;
  }
}

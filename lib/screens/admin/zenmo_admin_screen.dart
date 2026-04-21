import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_fingerprint_service.dart';

/// Streams all fingerprint submissions and displays them as cards.
/// Requirements: 6.1–6.5, 7.1–7.5
class ZenmoAdminScreen extends StatelessWidget {
  const ZenmoAdminScreen({super.key});

  static final _dateFmt = DateFormat('dd MMM yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final service = context.read<FirestoreFingerprintService>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Color(0xFF6366F1)),
        title: const Text(
          'Zenmo Admin',
          style: TextStyle(color: Colors.black87, fontSize: 18),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.streamAllSubmissions(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error: ${snap.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snap.data?.docs ?? [];

          // Expand each doc's submissions array into individual cards
          final cards = <_SubmissionCard>[];
          for (final doc in docs) {
            final data = doc.data();
            final uid = (data['uid'] as String?) ?? doc.id;
            final rawSubs = data['submissions'];
            if (rawSubs is! List || rawSubs.isEmpty) continue;

            // Most recent first
            final subs = rawSubs.reversed.toList();
            for (final sub in subs) {
              if (sub is Map) {
                cards.add(_SubmissionCard(
                  uid: uid,
                  submission: Map<String, dynamic>.from(sub),
                ));
              }
            }
          }

          if (cards.isEmpty) {
            return const Center(
              child: Text(
                'No submissions yet.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => cards[i],
          );
        },
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.uid, required this.submission});

  final String uid;
  final Map<String, dynamic> submission;

  String _truncateUid(String uid) =>
      uid.length > 12 ? '${uid.substring(0, 12)}…' : uid;

  String _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      return ZenmoAdminScreen._dateFmt.format(ts.toDate().toLocal());
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final answers = submission['answers'];
    final submittedAt = submission['submittedAt'];

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
            // Header row
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  _truncateUid(uid),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTimestamp(submittedAt),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const Divider(height: 20),

            // Answers
            if (answers is List)
              ...answers.map((a) {
                if (a is! Map) return const SizedBox.shrink();
                final answer = Map<String, dynamic>.from(a);
                final qIndex = (answer['questionIndex'] as int?) ?? 0;
                final qText = (answer['questionText'] as String?) ??
                    'Question ${qIndex + 1}';
                final titles = (answer['titles'] as List?)
                        ?.map((e) => e?.toString() ?? '')
                        .toList() ??
                    [];
                final hexValues = (answer['hexValues'] as List?)
                        ?.map((e) => e?.toString() ?? '')
                        .toList() ??
                    [];
                final colorInts = (answer['colorInts'] as List?)
                        ?.whereType<int>()
                        .toList() ??
                    [];
                final notes = (answer['notes'] as List?)
                        ?.map((e) => e?.toString())
                        .toList() ??
                    [];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Q${qIndex + 1}: $qText',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (colorInts.isEmpty)
                        const Text(
                          'No colors',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        )
                      else
                        ...List.generate(colorInts.length, (i) {
                          final color = Color(colorInts[i]);
                          final title =
                              i < titles.length ? titles[i] : '';
                          final hex =
                              i < hexValues.length ? hexValues[i] : '';
                          final note =
                              i < notes.length ? notes[i] : null;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: Colors.black12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  hex.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: Colors.grey,
                                  ),
                                ),
                                if (note != null && note.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '— $note',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MyRewardsScreen extends StatelessWidget {
  const MyRewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rewards')),
        body: const Center(child: Text('You must be signed in.')),
      );
    }

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);

    // IMPORTANT: do NOT require createdAt for query ordering.
    // Some reward docs may not have it yet; ordering would then error.
    final rewardsQuery = userDocRef.collection('rewards');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocRef.snapshots(),
      builder: (context, userSnap) {
        if (userSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Rewards')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Could not load your rewards data.\n\n${userSnap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (!userSnap.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Rewards')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final userData = userSnap.data?.data() ?? const <String, dynamic>{};
        final sentCount = (userData['totalSentCount'] as int?) ?? 0;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: rewardsQuery.snapshots(),
          builder: (context, rewardsSnap) {
            final Object? rewardsError = rewardsSnap.error;
            final bool rewardsLoading =
                rewardsSnap.connectionState == ConnectionState.waiting &&
                rewardsSnap.data == null;

            final docs = rewardsSnap.data?.docs ?? const [];

            // Stable client-side sort:
            // 1) createdAt desc if present
            // 2) else by threshold desc if present
            // 3) else by doc id (stable)
            final sorted = [...docs];
            sorted.sort((a, b) {
              final ad = a.data();
              final bd = b.data();

              final aCreated = ad['createdAt'];
              final bCreated = bd['createdAt'];

              Timestamp? at;
              Timestamp? bt;
              if (aCreated is Timestamp) at = aCreated;
              if (bCreated is Timestamp) bt = bCreated;

              if (at != null && bt != null) {
                return bt.compareTo(at);
              }
              if (at != null && bt == null) return -1;
              if (at == null && bt != null) return 1;

              final aTh = ad['threshold'];
              final bTh = bd['threshold'];
              final int ath = (aTh is int) ? aTh : -1;
              final int bth = (bTh is int) ? bTh : -1;

              if (ath != bth) return bth.compareTo(ath);
              return b.id.compareTo(a.id);
            });

            // Milestones config
            const milestones = <int>[1, 3, 5, 10, 20, 50, 100, 200, 500, 1000];

            final currentTier = _tierForCount(sentCount);
            final nextThreshold = _nextThreshold(sentCount);

            return Scaffold(
              backgroundColor: const Color(0xFFF7F0FA),
              appBar: AppBar(
                title: const Text('Rewards'),
                backgroundColor: const Color(0xFFF7F0FA),
                elevation: 0,
                foregroundColor: Colors.black,
              ),
              body: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: _ProgressCard(
                        sentCount: sentCount,
                        currentTier: currentTier,
                        nextThreshold: nextThreshold,
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 6)),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Your rewards',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 10)),

                  if (rewardsError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _ErrorState(
                          title: 'Could not load rewards',
                          message: rewardsError.toString(),
                        ),
                      ),
                    )
                  else if (rewardsLoading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: _LoadingRewardsState(),
                      ),
                    )
                  else if (sorted.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _EmptyState(
                          sent: sentCount,
                          nextTh: nextThreshold,
                        ),
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _RewardRow(doc: sorted[index]),
                        );
                      },
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 18)),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Milestones',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 10)),

                  SliverList.separated(
                    itemCount: milestones.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final th = milestones[index];
                      final achieved = sentCount >= th;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _MilestoneRow(threshold: th, achieved: achieved),
                      );
                    },
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String _tierForCount(int sent) {
    if (sent >= 100) return 'Zenmo Hall of Fame';
    if (sent >= 50) return 'Zenmo Legend';
    if (sent >= 20) return 'Zenmo Hero';
    if (sent >= 10) return 'Zenmo Regular';
    if (sent >= 5) return 'Zenmo Starter';
    if (sent >= 1) return 'Zenmo Newbie';
    return 'Getting started';
  }

  static int _nextThreshold(int sent) {
    const thresholds = <int>[1, 3, 5, 10, 20, 50, 100];
    for (final t in thresholds) {
      if (sent < t) return t;
    }
    return 100;
  }
}

class _ProgressCard extends StatelessWidget {
  final int sentCount;
  final String currentTier;
  final int nextThreshold;

  const _ProgressCard({
    required this.sentCount,
    required this.currentTier,
    required this.nextThreshold,
  });

  @override
  Widget build(BuildContext context) {
    final int next = nextThreshold;
    final int prev = _prevThreshold(next);
    final int span = (next - prev).clamp(1, 999999);
    final double progress =
        ((sentCount - prev) / span).clamp(0.0, 1.0).toDouble();

    final int remaining = (next - sentCount).clamp(0, 999999);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 8),
            color: Color(0x19000000),
          ),
        ],
        border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Progress', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            "You've sent $sentCount Zenmos",
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Current: $currentTier',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            remaining == 0
                ? 'Unlocked!'
                : '$remaining more Zenmos to unlock: ${MyRewardsScreen._tierForCount(next)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: const Color(0xFFEAE2F3),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF6D4FA3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static int _prevThreshold(int next) {
    const thresholds = <int>[0, 1, 3, 5, 10, 20, 50, 100];
    int prev = 0;
    for (final t in thresholds) {
      if (t < next) prev = t;
    }
    return prev;
  }
}

class _LoadingRewardsState extends StatelessWidget {
  const _LoadingRewardsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: const [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading rewards…',
              style: TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String title;
  final String message;
  const _ErrorState({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: Colors.black87)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final int sent;
  final int nextTh;
  const _EmptyState({required this.sent, required this.nextTh});

  @override
  Widget build(BuildContext context) {
    final int remaining = (nextTh - sent).clamp(0, 999999);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Text(
        remaining == 0
            ? 'No rewards listed yet.\n(You may already have unlocked tiers — we just need the reward docs to exist.)'
            : 'No rewards yet.\nSend a few Zenmos and check back here.\n\n$remaining more to your next milestone.',
        style: const TextStyle(fontSize: 14, color: Colors.black87),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _RewardRow({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();

    final title = (d['title'] as String?) ?? 'Reward';
    final description = (d['description'] as String?) ?? '';
    final status = (d['status'] as String?) ?? 'unfulfilled';

    final bool fulfilled = status == 'fulfilled' || status == 'claimed';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusChip(fulfilled: fulfilled),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final int threshold;
  final bool achieved;

  const _MilestoneRow({required this.threshold, required this.achieved});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: achieved ? const Color(0xFFE6F6EA) : Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            achieved ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: achieved ? const Color(0xFF2E7D32) : Colors.black45,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$threshold • ${_labelForThreshold(threshold)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'You sent $threshold Zenmo${threshold == 1 ? '' : 's'}.',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _labelForThreshold(int t) {
    switch (t) {
      case 1:
        return 'First Zenmo!';
      case 3:
        return 'Three Zenmos';
      case 5:
        return 'Five Zenmos';
      case 10:
        return 'Ten Zenmos';
      case 20:
        return 'Twenty Zenmos';
      case 50:
        return 'Fifty Zenmos';
      case 100:
        return 'One Hundred Zenmos';
      case 200:
        return 'Two Hundred Zenmos';
      case 500:
        return 'Five Hundred Zenmos';
      case 1000:
        return 'One Thousand Zenmos';
      default:
        return 'Milestone';
    }
  }
}

class _StatusChip extends StatelessWidget {
  final bool fulfilled;
  const _StatusChip({required this.fulfilled});

  @override
  Widget build(BuildContext context) {
    final text = fulfilled ? 'CLAIMED' : 'UNCLAIMED';
    final bg = fulfilled ? const Color(0xFFE6F6EA) : const Color(0xFFF2F2F2);
    final fg = fulfilled ? const Color(0xFF2E7D32) : Colors.black87;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: fg,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

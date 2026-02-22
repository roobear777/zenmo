import 'package:color_wallet/widgets/wallet_badge_icon.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:async/async.dart'; // StreamZip
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

// DEBUG
import 'package:color_wallet/debug/keeps_debug.dart';

// Models
import '../models/answer.dart';
import '../models/keep.dart';

// Repos & services
import '../services/swatch_repository.dart';
import '../services/user_identity_service.dart';
import '../services/firestore/answer_repository_firestore.dart';
import '../services/firestore/keep_repository_firestore.dart';
import '../services/paged.dart';
import '../services/public_feed_repository.dart';

// UI
import 'review_screen.dart';
import 'color_picker_screen.dart';
import 'daily_hues/daily_hues_screen.dart';
import 'menu.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.initialTab = 0});

  /// 0 = Inbox, 1 = Drafts, 2 = Sent
  final int initialTab;

  static const routeName = '/wallet';

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final SwatchRepository _swatchRepository = SwatchRepository();
  final UserIdentityService _userIdentityService = UserIdentityService();

  // Kept
  final _keepRepo = KeepRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );
  final _answerRepo = AnswerRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );
  final PublicFeedRepository _publicRepo = PublicFeedRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );
  String? _openingSwatchId; // prevents duplicate/blocked opens on quick taps

  // NOTE: Drafts/Sent can stay as Futures (not hot paths); Inbox becomes a Stream for instant cached paint.
  late Future<List<Map<String, dynamic>>> _draftSwatchesFuture;
  late Future<List<Map<String, dynamic>>> _sentSwatchesFuture;

  // NEW: live inbox stream (cache-first)
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _inboxStream;

  late final Stream<int> _unreadCountStream;
  late final Stream<int> _heartsUnreadCountStream;
  late final Stream<int> _keptUnreadCountStream;
  late final Stream<int> _combinedUnreadStream;

  final Map<String, String> _userNameCache = {};
  Future<String> _getDisplayNameFor(String uid) async {
    if (uid.isEmpty) return 'Unknown user';
    final cached = _userNameCache[uid];
    if (cached != null) return cached;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name = (doc.data()?['displayName'] as String?)?.trim();
      final resolved = (name == null || name.isEmpty) ? uid : name;
      _userNameCache[uid] = resolved;
      return resolved;
    } catch (_) {
      return uid;
    }
  }

  @override
  void initState() {
    super.initState();

    print('[Wallet] initState fired');

    _buildStreamsAndFutures();

    // If you already wired this, leave it here:
    KeepsDebug.runOnce();

    // existing badge streams
    _unreadCountStream = _swatchRepository.inboxUnreadCountStream();
    _heartsUnreadCountStream = _swatchRepository.heartsUnreadCountStream();

    // unread keeps for current user
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _keptUnreadCountStream =
        (uid == null)
            ? Stream<int>.value(0)
            : FirebaseFirestore.instance
                .collection('keeps')
                .where('userId', isEqualTo: uid)
                .snapshots()
                .map(
                  (qs) =>
                      qs.docs.where((d) => (d.data()['readAt'] == null)).length,
                );

    _combinedUnreadStream = StreamZip<int>([
      _unreadCountStream,
      _keptUnreadCountStream,
    ]).map(
      // Wallet badge = Inbox unread + Kept unread (hearts excluded)
      (vals) => vals[0] + vals[1],
    );
  }

  void _buildStreamsAndFutures() {
    // Inbox — Stream with cache-first snapshots for instant UI
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _inboxStream = FirebaseFirestore.instance
          .collectionGroup('userSwatches')
          .where('recipientId', isEqualTo: uid)
          .where('status', isEqualTo: 'sent')
          .orderBy('sentAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true) // tiebreaker
          .limit(48)
          .snapshots(includeMetadataChanges: true);
    } else {
      _inboxStream = const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    // Drafts/Sent keep current repo futures (not on critical path)
    _draftSwatchesFuture = _swatchRepository.loadDraftSwatches();
    _sentSwatchesFuture = _swatchRepository.loadSentSwatches();
  }

  void _reloadTab(int index) {
    // Only drafts/sent need a refresh; inbox is a live stream.
    if (index == 0) return;
    if (index == 1) {
      setState(
        () => _draftSwatchesFuture = _swatchRepository.loadDraftSwatches(),
      );
    } else if (index == 2) {
      setState(
        () => _sentSwatchesFuture = _swatchRepository.loadSentSwatches(),
      );
    }
  }

  void _onNavBarTap(int index) {
    if (index == 0) {
      // no-op; inbox stream is already live
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ColorPickerScreen()),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DailyHuesScreen()),
      );
    }
  }

  Future<void> _confirmAndDelete(String swatchId, String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Swatch'),
            content: const Text('Are you sure you want to delete this swatch?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await _swatchRepository.deleteSwatch(swatchId: swatchId, userId: userId);
      _reloadTab(0);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted')));
    }
  }

  Future<void> _confirmAndHideInbox({
    required String senderId,
    required String swatchId,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Swatch'),
            content: const Text(
              'Are you sure you want to delete this swatch from your inbox? This won’t affect the sender’s copy.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await _swatchRepository.hideForRecipient(
        senderId: senderId,
        swatchId: swatchId,
        hidden: true,
      );
      if (!mounted) return;
      _reloadTab(0);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted')));
    }
  }

  Future<void> _markAsReadIfNeeded({
    required String swatchId,
    required String? senderId,
    required bool isInbox,
    required bool wasUnread,
  }) async {
    if (!isInbox || !wasUnread) return;
    if (swatchId.isEmpty || senderId == null || senderId.isEmpty) return;
    await _swatchRepository.markRead(senderId: senderId, swatchId: swatchId);
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dateTime.year, dateTime.month, dateTime.day);
    if (target == today) return 'Today';
    if (dateTime.year == 2000) return 'Unknown date';
    return DateFormat('MMMM d, y').format(dateTime);
  }

  Color _tileColor(Map<String, dynamic> m) {
    final dynamic raw = m['color'];
    if (raw is int) {
      final solid = (raw & 0x00FFFFFF) | 0xFF000000;
      return Color(solid);
    }
    final String? hex = (m['colorHex'] as String?)?.trim();
    if (hex == null || hex.isEmpty) return const Color(0xFF000000);
    var s = hex.startsWith('#') ? hex.substring(1) : hex;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return const Color(0xFF000000);
    if (s.length == 6) return Color(0xFF000000 | v);
    if (s.length == 8) return Color(0xFF000000 | (v & 0x00FFFFFF));
    return const Color(0xFF000000);
  }

  // ---------- UI builders ----------

  Widget _buildSwatchGrid(List<Map<String, dynamic>> swatches, String type) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: swatches.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) {
        final swatch = swatches[index];

        final color = _tileColor(swatch);
        final title = (swatch['title'] ?? '') as String;
        final swatchId = (swatch['id'] ?? '') as String;
        final senderId = swatch['senderId'] as String?;
        final recipientId = swatch['recipientId'] as String?;

        final createdAt = swatch['createdAt'] as Timestamp?;
        final sentAt = swatch['sentAt'] as Timestamp?;
        final dateTime =
            (type == 'inbox'
                ? sentAt?.toDate()
                : type == 'sent'
                ? sentAt?.toDate()
                : createdAt?.toDate()) ??
            DateTime(2000);

        final bool isInbox = (type == 'inbox');
        final bool isDraft = (type == 'draft');
        final bool unread = isInbox && (swatch['readAt'] == null);

        // ----- Kept detection (effective) -----
        final bool isKeptExplicit = swatch['isKept'] == true;
        final String? myUid = FirebaseAuth.instance.currentUser?.uid;
        final bool isSelfSentInbox =
            isInbox && myUid != null && senderId == myUid;
        final bool hasKeepDoc =
            (swatch['keptId'] is String) &&
            (swatch['keptId'] as String).isNotEmpty;
        final bool isKeptEffective =
            isKeptExplicit || isSelfSentInbox || hasKeepDoc;

        final String statusText = _formatDateTime(dateTime);

        String name = (swatch['senderName'] ?? 'Anonymous') as String;
        if (type == 'draft') {
          final myName = _userIdentityService.currentDisplayName.toLowerCase();
          if (name.toLowerCase() == myName) name = '(You)';
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            if (_openingSwatchId != null) return;
            _openingSwatchId = swatchId;

            try {
              final bool wasUnread = isInbox && (swatch['readAt'] == null);

              // Optimistic local read mark
              if (wasUnread) {
                setState(() {
                  swatch['readAt'] = Timestamp.now();
                });
              }

              // Fire-and-forget read write
              Future<void>(() async {
                try {
                  // If this tile has a keep doc, mark that as read.
                  if (isInbox && hasKeepDoc) {
                    final String keptId =
                        (swatch['keptId'] ?? swatchId) as String;
                    await _keepRepo.markReadKept(keptId);
                  }

                  // Always mark the inbox userSwatches doc as read for inbox tiles.
                  await _markAsReadIfNeeded(
                    swatchId: swatchId,
                    senderId: senderId,
                    isInbox: isInbox,
                    wasUnread: wasUnread,
                  );
                } catch (_) {
                  if (wasUnread && mounted) {
                    // Roll back optimistic local update if the write failed.
                    setState(() => swatch['readAt'] = null);
                  }
                }
              });

              if (!mounted) return;

              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (_) => ReviewScreen(
                        selectedColor: color,
                        title: title,
                        message: swatch['message'] ?? '',
                        creatorName: name,
                        timestamp: dateTime,
                        swatchId: swatchId,
                        senderId: senderId,
                        isSent: !isDraft,
                        isDraft: isDraft,
                        rootId: swatch['rootId'] as String?,
                      ),
                ),
              );

              if (mounted) _reloadTab(0);
            } finally {
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _openingSwatchId = null;
                });
              } else {
                _openingSwatchId = null;
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: unread ? Colors.black87 : Colors.grey.shade300,
                width: unread ? 3.5 : 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip:
                            (isInbox && hasKeepDoc)
                                ? 'Remove from Wallet'
                                : 'Delete',
                        icon: const Icon(Icons.delete, size: 20),
                        color: Colors.black54,
                        padding: const EdgeInsets.all(0),
                        onPressed: () async {
                          if (isInbox) {
                            if (hasKeepDoc) {
                              try {
                                final String keptId =
                                    (swatch['keptId'] ?? swatchId) as String;
                                final kept = await _keepRepo.toggleKeep(keptId);
                                if (!kept && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Removed from Wallet'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Remove failed: $e'),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) _reloadTab(0);
                              }
                            } else {
                              if (senderId == null) return;
                              await _confirmAndHideInbox(
                                senderId: senderId,
                                swatchId: swatchId,
                              );
                            }
                          } else {
                            final ownerId =
                                senderId ??
                                await _userIdentityService.getCurrentUserId();
                            if (!mounted) return;
                            await _confirmAndDelete(swatchId, ownerId);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.isEmpty ? '(untitled)' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (isInbox && isKeptEffective)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Kept',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                // Inbox: tiny avatar + sender name (Drafts/Sent unchanged)
                if (type == 'inbox')
                  Row(
                    children: [
                      _MiniAvatar(uid: senderId, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else if (type != 'sent')
                  Text(
                    name,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  statusText,
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- Sent list (unchanged logic; note: one FutureBuilder per row can be optimized later) ----------

  Widget _buildSentList(List<Map<String, dynamic>> swatches) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: swatches.length,
      separatorBuilder:
          (_, __) => const Divider(height: 1, color: Color(0xFFE9E9E9)),
      itemBuilder: (context, index) {
        final swatch = swatches[index];

        final color = _tileColor(swatch);
        final title = (swatch['title'] ?? '') as String;
        final swatchId = (swatch['id'] ?? '') as String;
        final senderId = swatch['senderId'] as String?;
        final recipientId = swatch['recipientId'] as String?;

        final sentAt = swatch['sentAt'] as Timestamp?;
        final dateTime = sentAt?.toDate() ?? DateTime(2000);

        final bool isHearted =
            (swatch['hearted'] == true) ||
            (swatch['recipientHearted'] == true) ||
            ((swatch['heartCount'] ?? 0) > 0);

        return FutureBuilder<String>(
          future:
              recipientId == null
                  ? Future.value('Unknown')
                  : _getDisplayNameFor(recipientId),
          builder: (context, snap) {
            final toName = snap.data ?? (recipientId ?? 'Unknown');
            return InkWell(
              onTap: () async {
                try {
                  final myUid = await _userIdentityService.getCurrentUserId();
                  if (senderId != null &&
                      senderId == myUid &&
                      swatch['hearted'] == true &&
                      swatch['heartedSeen'] != true) {
                    await _swatchRepository.markHeartSeen(
                      senderId: senderId,
                      swatchId: swatchId,
                    );
                  }
                } catch (_) {}

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => ReviewScreen(
                          selectedColor: color,
                          title: title,
                          message: swatch['message'] ?? '',
                          creatorName: swatch['senderName'] ?? 'Anonymous',
                          timestamp: dateTime,
                          swatchId: swatchId,
                          senderId: senderId,
                          isSent: true,
                          isDraft: false,
                          rootId: swatch['rootId'] as String?,
                        ),
                  ),
                );
                if (mounted) _reloadTab(2);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty ? '(untitled)' : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'To: $toName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDateTime(dateTime),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isHearted)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.favorite,
                          size: 20,
                          color: Colors.black87,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.black45,
                      ),
                      onPressed: () async {
                        final ownerId =
                            senderId ??
                            await _userIdentityService.getCurrentUserId();
                        _confirmAndDelete(swatchId, ownerId);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 1,
              automaticallyImplyLeading: true,
              centerTitle: true,
              title: const Text(
                'Wallet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              actions: const [ZenmoMenuButton(isOnWallet: true)],
            ),
            Expanded(
              child: DefaultTabController(
                length: 3,
                initialIndex: widget.initialTab,
                child: Column(
                  children: [
                    const TabBar(
                      labelColor: Colors.black,
                      indicatorColor: Colors.black,
                      tabs: [
                        Tab(text: 'Inbox'),
                        Tab(text: 'Drafts'),
                        Tab(text: 'Sent'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // ---------- Inbox (STREAM: cache-first; overlay kept when ready) ----------
                          SingleChildScrollView(
                            child: StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>
                            >(
                              stream: _inboxStream,
                              builder: (context, snap) {
                                // Cache-first: if nothing yet, show light skeleton (not spinner)
                                if (!snap.hasData) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    child: _buildSkeletonGrid(6),
                                  );
                                }

                                // Build inbox from current snapshot (cache or server)
                                final docs = snap.data!.docs;
                                final List<Map<String, dynamic>> inbox =
                                    docs
                                        .map((d) {
                                          final m = d.data();
                                          m['id'] = d.id;

                                          // Inject senderId from path if missing (legacy)
                                          final sidInDoc = m['senderId'];
                                          if (sidInDoc == null ||
                                              (sidInDoc is String &&
                                                  sidInDoc.isEmpty)) {
                                            try {
                                              final sid =
                                                  d.reference.parent.parent?.id;
                                              if (sid != null) {
                                                m['senderId'] = sid;
                                              }
                                            } catch (_) {}
                                          }
                                          return m;
                                        })
                                        .where(
                                          (m) =>
                                              m['hiddenForRecipient'] != true,
                                        )
                                        .toList();

                                // If inbox still empty, show empty-state now (don’t block on keeps)
                                if (inbox.isEmpty) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text('No received swatches.'),
                                    ),
                                  );
                                }

                                // In parallel, fetch kept and overlay when ready (don’t block inbox).
                                return FutureBuilder<Paged<Keep>>(
                                  future: _keepRepo.getKeepsForCurrentUser(
                                    limit: 24,
                                  ),
                                  builder: (context, keepSnap) {
                                    final keptPage = keepSnap.data;
                                    final keptItems =
                                        keptPage?.items ?? const <Keep>[];

                                    // Build kept lookup: answerId -> keptId (keep doc id)
                                    final Map<String, String> keptIdByAnswerId =
                                        {};
                                    for (final k in keptItems) {
                                      if (k.answerId.isNotEmpty) {
                                        keptIdByAnswerId[k.answerId] = k.id;
                                      }
                                    }

                                    // Tag inbox items that are kept/self-sent
                                    void tagInboxWithKept() {
                                      final myUid =
                                          FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid;
                                      for (final m in inbox) {
                                        if (m['isKept'] == true) continue;
                                        final String? rootId =
                                            m['rootId'] as String?;
                                        final String? parentId =
                                            m['parentId'] as String?;
                                        final String? id = m['id'] as String?;
                                        String? matchKeptId;
                                        if (rootId != null &&
                                            keptIdByAnswerId.containsKey(
                                              rootId,
                                            )) {
                                          matchKeptId =
                                              keptIdByAnswerId[rootId];
                                        } else if (parentId != null &&
                                            keptIdByAnswerId.containsKey(
                                              parentId,
                                            )) {
                                          matchKeptId =
                                              keptIdByAnswerId[parentId];
                                        } else if (id != null &&
                                            keptIdByAnswerId.containsKey(id)) {
                                          matchKeptId = keptIdByAnswerId[id];
                                        }
                                        final bool selfSent =
                                            (myUid != null &&
                                                m['senderId'] == myUid);
                                        if (matchKeptId != null) {
                                          m['isKept'] = true;
                                          m['keptId'] = matchKeptId;
                                        } else if (selfSent) {
                                          m['isKept'] = true;
                                        }
                                      }
                                    }

                                    tagInboxWithKept();

                                    // If kept still loading, just show inbox now.
                                    if (keepSnap.connectionState ==
                                        ConnectionState.waiting) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 16,
                                        ),
                                        child: _buildSwatchGrid(inbox, 'inbox'),
                                      );
                                    }

                                    // Map kept into tiles and merge with inbox (then sort by sent/created)
                                    Future<List<Map<String, dynamic>>>
                                    mapKept() async {
                                      if (keptItems.isEmpty) {
                                        return <Map<String, dynamic>>[];
                                      }

                                      final answers = await Future.wait(
                                        keptItems.map(
                                          (k) => _answerRepo.getAnswerById(
                                            k.answerId,
                                          ),
                                        ),
                                      );

                                      final List<Map<String, dynamic>> out = [];
                                      for (
                                        var i = 0;
                                        i < keptItems.length;
                                        i++
                                      ) {
                                        final keep = keptItems[i];
                                        final Answer? a =
                                            (i < answers.length)
                                                ? answers[i]
                                                : null;

                                        if (a != null) {
                                          final responderId =
                                              a.responderId ?? '';
                                          final displayName =
                                              responderId.isEmpty
                                                  ? 'Anonymous'
                                                  : await _getDisplayNameFor(
                                                    responderId,
                                                  );

                                          out.add({
                                            'id': a.id,
                                            'title':
                                                a.title.isEmpty
                                                    ? a.colorHex
                                                    : a.title,
                                            'message': '',
                                            'senderName': displayName,
                                            'colorHex': a.colorHex,
                                            'sentAt': Timestamp.fromDate(
                                              a.createdAt,
                                            ),
                                            'createdAt': Timestamp.fromDate(
                                              a.createdAt,
                                            ),
                                            'readAt':
                                                keep.readAt == null
                                                    ? null
                                                    : Timestamp.fromDate(
                                                      keep.readAt!,
                                                    ),
                                            'senderId': a.responderId,
                                            'rootId': a.id,
                                            'kept': true,
                                            'isKept': true,
                                            'keptId': keep.id,
                                          });
                                          continue;
                                        }

                                        // Fallback to public feed by rootId
                                        final f = await _publicRepo.getByRootId(
                                          keep.answerId,
                                        );
                                        if (f != null) {
                                          out.add({
                                            'id': f.rootId ?? keep.answerId,
                                            'title':
                                                f.title.isEmpty
                                                    ? f.colorHex
                                                    : f.title,
                                            'message': '',
                                            'senderName':
                                                f.creatorName.isEmpty
                                                    ? 'Anonymous'
                                                    : f.creatorName,
                                            'colorHex': f.colorHex,
                                            'sentAt': Timestamp.fromDate(
                                              f.sentAt ?? DateTime.now(),
                                            ),
                                            'createdAt': Timestamp.fromDate(
                                              f.sentAt ?? DateTime.now(),
                                            ),
                                            'readAt':
                                                keep.readAt == null
                                                    ? null
                                                    : Timestamp.fromDate(
                                                      keep.readAt!,
                                                    ),
                                            'senderId': null,
                                            'rootId': f.rootId ?? keep.answerId,
                                            'kept': true,
                                            'isKept': true,
                                            'keptId': keep.id,
                                          });
                                          continue;
                                        }

                                        // FINAL FALLBACK: render directly from keep snapshot fields
                                        if ((keep.colorHex != null) ||
                                            (keep.title != null) ||
                                            (keep.creatorName != null)) {
                                          out.add({
                                            'id': keep.answerId,
                                            'title':
                                                (keep.title ??
                                                            keep.colorHex ??
                                                            '')
                                                        .isEmpty
                                                    ? (keep.colorHex ??
                                                        '#000000')
                                                    : keep.title!,
                                            'message': '',
                                            'senderName':
                                                (keep.creatorName == null ||
                                                        keep
                                                            .creatorName!
                                                            .isEmpty)
                                                    ? 'Anonymous'
                                                    : keep.creatorName!,
                                            'colorHex':
                                                keep.colorHex ?? '#000000',
                                            'sentAt': Timestamp.fromDate(
                                              keep.sentAt ?? keep.createdAt,
                                            ),
                                            'createdAt': Timestamp.fromDate(
                                              keep.sentAt ?? keep.createdAt,
                                            ),
                                            'readAt':
                                                keep.readAt == null
                                                    ? null
                                                    : Timestamp.fromDate(
                                                      keep.readAt!,
                                                    ),
                                            'senderId': null,
                                            'rootId': keep.answerId,
                                            'kept': true,
                                            'isKept': true,
                                            'keptId': keep.id,
                                          });
                                        }
                                      }
                                      return out;
                                    }

                                    return FutureBuilder<
                                      List<Map<String, dynamic>>
                                    >(
                                      future: mapKept(),
                                      builder: (context, mappedKeptSnap) {
                                        final keptAsTiles =
                                            mappedKeptSnap.data ??
                                            const <Map<String, dynamic>>[];

                                        // De-duplication: prefer Inbox item; skip kept tile with same root/id.
                                        final Set<String> seenKeys = {
                                          for (final m in inbox)
                                            (m['rootId'] as String?) ??
                                                (m['id'] as String),
                                        };

                                        final List<Map<String, dynamic>>
                                        merged = [
                                          ...inbox,
                                          ...keptAsTiles.where((k) {
                                            final key =
                                                (k['rootId'] as String?) ??
                                                (k['id'] as String);
                                            if (seenKeys.contains(key)) {
                                              return false;
                                            }
                                            seenKeys.add(key);
                                            return true;
                                          }),
                                        ];

                                        DateTime extract(
                                          Map<String, dynamic> m,
                                        ) {
                                          final Timestamp? s =
                                              m['sentAt'] as Timestamp?;
                                          final Timestamp? c =
                                              m['createdAt'] as Timestamp?;
                                          return (s ??
                                                  c ??
                                                  Timestamp.fromDate(
                                                    DateTime(2000),
                                                  ))
                                              .toDate();
                                        }

                                        merged.sort(
                                          (a, b) =>
                                              extract(b).compareTo(extract(a)),
                                        );

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                          child: _buildSwatchGrid(
                                            merged,
                                            'inbox',
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),

                          // ---------- Drafts ----------
                          SingleChildScrollView(
                            child: FutureBuilder<List<Map<String, dynamic>>>(
                              future: _draftSwatchesFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    child: _buildSkeletonGrid(6),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return Center(
                                    child: Text('Error: ${snapshot.error}'),
                                  );
                                }
                                final drafts = snapshot.data ?? [];
                                if (drafts.isEmpty) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text('No drafts saved.'),
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                  child: _buildSwatchGrid(drafts, 'draft'),
                                );
                              },
                            ),
                          ),

                          // ---------- Sent ----------
                          SingleChildScrollView(
                            child: FutureBuilder<List<Map<String, dynamic>>>(
                              future: _sentSwatchesFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return Center(
                                    child: Text('Error: ${snapshot.error}'),
                                  );
                                }
                                final sent = snapshot.data ?? [];
                                if (sent.isEmpty) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text('No sent swatches.'),
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  child: _buildSentList(sent),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: _onNavBarTap,
        items: [
          BottomNavigationBarItem(
            label: 'Wallet',
            icon: WalletBadgeIcon(
              countStream: _combinedUnreadStream,
              icon: Icons.wallet,
            ),
            activeIcon: WalletBadgeIcon(
              countStream: _combinedUnreadStream,
              icon: Icons.wallet,
              selected: true,
            ),
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.brush),
            label: 'Send Vibes',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Daily Hues',
          ),
        ],
      ),
    );
  }

  // ---------- tiny skeleton grid for instant paint ----------
  Widget _buildSkeletonGrid(int count) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemBuilder:
          (_, __) => Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE6E6E6)),
            ),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8E8E8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Container(height: 12, color: const Color(0xFFE8E8E8)),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 80,
                  color: const Color(0xFFF0F0F0),
                ),
                const SizedBox(height: 4),
                Container(height: 9, width: 60, color: const Color(0xFFF5F5F5)),
              ],
            ),
          ),
    );
  }
}

/// Tiny inline avatar used in Inbox tiles.
/// Reads /users/{uid}/public/avatar { grid: List<List<String>> }.
/// If missing, falls back to /users/{uid}/private/fingerprint and computes 5×5.
class _MiniAvatar extends StatelessWidget {
  final String? uid;
  final double size;
  const _MiniAvatar({required this.uid, this.size = 14});

  // ---- helpers (local, no imports) ----
  static const _WHITE = '#FFFFFF';
  static const _GREY = '#E6E8ED';
  static const List<int> _SPIRAL = [
    12,
    13,
    18,
    17,
    16,
    11,
    6,
    7,
    8,
    9,
    14,
    19,
    24,
    23,
    22,
    21,
    20,
    15,
    10,
    5,
    0,
    1,
    2,
    3,
    4,
  ];

  Color _parseHex(String hex) {
    final s = hex.startsWith('#') ? hex.substring(1) : hex;
    final v = int.tryParse(s, radix: 16) ?? 0xE6E8ED; // grey fallback
    return Color(0xFF000000 | v);
  }

  List<List<String>> _checker() => List.generate(
    5,
    (r) => List.generate(5, (c) => ((r + c) % 2 == 0) ? _WHITE : _GREY),
  );

  String _intArgbToHex(int v) {
    final rgb = v & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  List<String> _normalizeHexList(List<dynamic>? raw) {
    if (raw == null) return const [];
    final out = <String>[];
    for (final x in raw) {
      if (x is int) {
        out.add(_intArgbToHex(x));
      } else if (x is String) {
        final s = x.startsWith('#') ? x.substring(1) : x;
        if (s.length == 6 && int.tryParse(s, radix: 16) != null) {
          out.add('#${s.toUpperCase()}');
        }
      }
    }
    return out;
  }

  List<List<String>> _gridFromColors(List<String> colors) {
    final grid = _checker();
    final n = colors.length.clamp(0, 25);
    for (int i = 0; i < n; i++) {
      final idx = _SPIRAL[i];
      final r = idx ~/ 5, c = idx % 5;
      grid[r][c] = colors[i].toUpperCase();
    }
    return grid;
  }

  Future<List<List<String>>> _loadGrid(String uid) async {
    final db = FirebaseFirestore.instance;

    // 1) Try public avatar (cache→server)
    final avatarRef = db
        .collection('users')
        .doc(uid)
        .collection('public')
        .doc('avatar');
    try {
      final cache = await avatarRef.get(const GetOptions(source: Source.cache));
      final snap = cache.exists ? cache : await avatarRef.get();
      final data = snap.data();
      if (data != null && data['grid'] is List) {
        final raw =
            (data['grid'] as List)
                .map<List>((row) => (row as List).cast())
                .toList();
        if (raw.length == 5 && raw.every((r) => r.length == 5)) {
          return List.generate(
            5,
            (r) => List.generate(5, (c) => (raw[r][c]?.toString() ?? _GREY)),
          );
        }
      }
    } catch (_) {
      // fall through to draft
    }

    // 2) Fallback: compute from draft fingerprint
    try {
      final draftRef = db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('fingerprint');
      final draft = (await draftRef.get()).data() ?? const <String, dynamic>{};
      final colors = _normalizeHexList(
        draft['answersHex'].isNotEmpty == true
            ? (draft['answersHex'] as List)
            : (draft['answers'] as List?),
      );
      if (colors.isNotEmpty) {
        return _gridFromColors(colors.take(25).toList());
      }
    } catch (_) {
      // ignore
    }

    // 3) Nothing available → checkerboard
    return _checker();
  }

  @override
  Widget build(BuildContext context) {
    if (uid == null || uid!.isEmpty) {
      return _box(_checker());
    }

    return FutureBuilder<List<List<String>>>(
      future: _loadGrid(uid!),
      builder: (context, snap) {
        final grid = snap.data ?? _checker();
        return _box(grid);
      },
    );
  }

  Widget _box(List<List<String>> grid) {
    final cell = size / 5;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26, width: 0.75),
          borderRadius: BorderRadius.circular(2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (r) {
              return SizedBox(
                width: size,
                height: cell,
                child: Row(
                  children: List.generate(5, (c) {
                    return SizedBox(
                      width: cell,
                      height: cell,
                      child: ColoredBox(color: _parseHex(grid[r][c])),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

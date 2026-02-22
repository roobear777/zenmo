import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/swatch_repository.dart';
import '../services/user_repository.dart';
import '../services/report_repository.dart';
import 'package:color_wallet/widgets/wallet_badge_icon.dart';

import 'wallet_screen.dart';
import 'account_screen.dart'; // (left in case other parts still use it)
import 'menu.dart';
import '../lineage_screen.dart';
import 'keepsake_options_screen.dart';
import 'color_picker_screen.dart';
import 'package:color_wallet/daily_hues/daily_hues_screen.dart';

// card-style safety menu
import '../widgets/safety_menu.dart';

class ReviewScreen extends StatefulWidget {
  final Color selectedColor;
  final String title;
  final String message;
  final String creatorName;
  final DateTime timestamp; // sentAt for sent/inbox; ignored for drafts
  final String? swatchId;

  /// Path owner (sender) of this swatch doc when opening from Inbox/Sent.
  /// May be null if caller only knows the swatchId; we will resolve.
  final String? senderId;

  /// Is this already sent? (Inbox/Sent: true, Draft: false)
  final bool isSent;

  final bool isDraft;
  final bool showRecipientDropdown;

  /// Lineage root id, if your list already has it (optional; we'll fetch if missing).
  final String? rootId;

  /// If Create/ColorPicker preselected a recipient, pass it here.
  final String? preselectedRecipientId;
  final String? preselectedRecipientName;

  const ReviewScreen({
    super.key,
    required this.selectedColor,
    required this.title,
    required this.message,
    required this.creatorName,
    required this.timestamp,
    this.swatchId,
    this.senderId,
    this.isSent = false,
    this.isDraft = false,
    this.showRecipientDropdown = false,
    this.rootId,
    this.preselectedRecipientId,
    this.preselectedRecipientName,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with SingleTickerProviderStateMixin {
  DateTime? sentTimestamp; // set after sending here
  final _repo = SwatchRepository();
  final _reportRepo = ReportRepository();
  bool _marked = false;

  String? selectedRecipientId;
  List<AppUser> users = [];
  bool isSending = false;
  bool hasSent = false; // flips true after sending here
  bool showSentBanner = false;

  // Heart + lineage
  bool? hearted; // null until known; then true/false
  String? heartedByName; // for creator-side display
  String? _rootId; // lineage root id

  // ── Resolved root creator display name (for FROM line fallback) ────────────
  String? _resolvedCreatorName;

  // When only swatchId is provided, we resolve senderId via CG query.
  String? _resolvedSenderId;

  // optional message when re-sending
  final TextEditingController _forwardMsgCtrl = TextEditingController();

  // Authoritative: am I the recipient of this SENT swatch?
  bool? _isReceivedMeta;

  // Kept state for current user (used to flip Keep/Unkeep in Wallet -> Kept flow)
  bool _keptKnown = false;
  bool _isKept = false;

  // Latest sender display name for this specific hop (what "FROM" should show)
  String? _currentSenderName;

  late AnimationController _bannerController;
  late Animation<Offset> slideAnimation;
  late Animation<double> fadeAnimation;

  // NEW: post-send navigation timer (so we can cancel if user navigates away)
  Timer? _postSendNavTimer;

  @override
  void initState() {
    super.initState();

    _rootId = widget.rootId;

    // IMPORTANT: do NOT path-read with widget.senderId here.
    // Resolve via CG first; then do any path reads/updates safely.
    _ensureSenderAndMeta().then((_) async {
      await _refreshKeptState();
      await _loadRootCreatorName(); // resolve true root creator for FROM fallback
      await _loadCurrentSenderName(); // resolve latest sender display name
    });

    // Prefill selection from preselected id (if any)
    selectedRecipientId = widget.preselectedRecipientId;

    _fetchUsers();

    _bannerController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _bannerController, curve: Curves.easeOut),
    );
    fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _bannerController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeIn),
      ),
    );

    // NOTE: removed addPostFrameCallback markRead here.
    // We mark read only after senderId is resolved in _ensureSenderAndMeta().
  }

  /// Resolve senderId (and rootId/heart/read) when we only know swatchId.
  Future<void> _ensureSenderAndMeta() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || widget.swatchId == null) return;

    try {
      final db = FirebaseFirestore.instance;

      DocumentSnapshot<Map<String, dynamic>>? doc;

      if (widget.senderId == null) {
        final qsRecipient =
            await db
                .collectionGroup('userSwatches')
                .where(FieldPath.documentId, isEqualTo: widget.swatchId)
                .where('recipientId', isEqualTo: myUid)
                .limit(1)
                .get();

        if (qsRecipient.docs.isNotEmpty) {
          doc = qsRecipient.docs.first;
        } else {
          final qsSender =
              await db
                  .collectionGroup('userSwatches')
                  .where(FieldPath.documentId, isEqualTo: widget.swatchId)
                  .where('senderId', isEqualTo: myUid)
                  .limit(1)
                  .get();
          if (qsSender.docs.isNotEmpty) {
            doc = qsSender.docs.first;
          }
        }
      } else {
        final qs =
            await db
                .collectionGroup('userSwatches')
                .where(FieldPath.documentId, isEqualTo: widget.swatchId)
                .limit(1)
                .get();
        if (qs.docs.isNotEmpty) doc = qs.docs.first;
      }

      if (doc == null) return;

      final data = doc.data() ?? const {};
      final senderId = (data['senderId'] as String?) ?? '';
      final recip = data['recipientId'] as String?;
      final status = data['status'] as String?;

      setState(() {
        _resolvedSenderId = senderId.isNotEmpty ? senderId : null;
        if (_rootId == null && data['rootId'] is String) {
          _rootId = data['rootId'] as String;
        }
        _isReceivedMeta = (recip == myUid && status == 'sent');
      });

      if (!_marked &&
          senderId.isNotEmpty &&
          senderId != myUid &&
          widget.swatchId != null &&
          (_isReceivedMeta == true)) {
        try {
          await _repo.markRead(senderId: senderId, swatchId: widget.swatchId!);
          _marked = true;
        } catch (_) {}
      }

      if (widget.swatchId != null && senderId.isNotEmpty) {
        await _loadHeartMeta(senderId, widget.swatchId!);
      }
    } catch (_) {}
  }

  /// Discover whether *current user* has kept this item (by rootId).
  Future<void> _refreshKeptState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final root = _rootId ?? widget.rootId ?? widget.swatchId;
    if (uid == null || root == null) return;

    try {
      final qs =
          await FirebaseFirestore.instance
              .collection('keeps')
              .where('userId', isEqualTo: uid)
              .where('answerId', isEqualTo: root)
              .limit(1)
              .get();

      if (!mounted) return;
      setState(() {
        _keptKnown = true;
        _isKept = qs.docs.isNotEmpty;
      });
    } catch (_) {}
  }

  // ── Load true root creator from lineage and cache for fallback ────────────
  Future<void> _loadRootCreatorName() async {
    try {
      // Choose the lineage root to query.
      final String? root = _rootId ?? widget.rootId ?? widget.swatchId;
      if (root == null || root.isEmpty) {
        if (_resolvedCreatorName == null && mounted) {
          setState(() => _resolvedCreatorName = widget.creatorName);
        }
        return;
      }

      // Ask repo for lineage events.
      final events = await _repo.getLineage(root);

      String? rootCreatorId;
      String? rootCreatorName;

      String? s(dynamic v) =>
          (v is String && v.trim().isNotEmpty) ? v.trim() : null;

      if (events.isNotEmpty) {
        // 1) Prefer any explicit rootCreator* fields exposed in events.
        for (final e in events) {
          if (e is Map) {
            rootCreatorId ??= s(e['rootCreatorId']);
            rootCreatorName ??= s(e['rootCreatorName']);
            if (rootCreatorId != null && rootCreatorName != null) break;
          }
        }
        // 2) If still missing, use the earliest event’s creator* as the root.
        if (rootCreatorId == null || rootCreatorName == null) {
          final first = events.first;
          if (first is Map) {
            rootCreatorId ??= s(first['creatorId']);
            rootCreatorName ??= s(first['creatorName']);
          }
        }
      }

      // Default to whatever the caller provided if lineage did not help.
      String resolved = widget.creatorName;
      final myUid = FirebaseAuth.instance.currentUser?.uid;

      if (rootCreatorId != null && myUid != null && rootCreatorId == myUid) {
        resolved = '(You)';
      } else if (rootCreatorName != null) {
        resolved = rootCreatorName;
      }

      if (mounted) {
        setState(() => _resolvedCreatorName = resolved);
      }
    } catch (_) {
      if (mounted && _resolvedCreatorName == null) {
        setState(() => _resolvedCreatorName = widget.creatorName);
      }
    }
  }

  /// Resolve the *latest sender* display name for this swatch.
  /// Used for the "FROM:" line and the Lineage header.
  Future<void> _loadCurrentSenderName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final myUid = user?.uid;
      final sid = widget.senderId ?? _resolvedSenderId ?? myUid;

      if (sid == null || sid.isEmpty) {
        final fallback =
            (_resolvedCreatorName != null &&
                    _resolvedCreatorName!.trim().isNotEmpty)
                ? _resolvedCreatorName!.trim()
                : widget.creatorName;
        if (mounted) {
          setState(() => _currentSenderName = fallback);
        }
        return;
      }

      // If this hop is from me, show "(You)".
      if (myUid != null && sid == myUid) {
        if (mounted) {
          setState(() => _currentSenderName = '(You)');
        }
        return;
      }

      final doc =
          await FirebaseFirestore.instance.collection('users').doc(sid).get();
      String? name;
      final data = doc.data();
      if (data != null && data['displayName'] is String) {
        final s = (data['displayName'] as String).trim();
        if (s.isNotEmpty) name = s;
      }

      name ??=
          (_resolvedCreatorName != null &&
                  _resolvedCreatorName!.trim().isNotEmpty)
              ? _resolvedCreatorName!.trim()
              : widget.creatorName;

      if (mounted) {
        setState(() => _currentSenderName = name);
      }
    } catch (_) {
      if (mounted && _currentSenderName == null) {
        final fallback =
            (_resolvedCreatorName != null &&
                    _resolvedCreatorName!.trim().isNotEmpty)
                ? _resolvedCreatorName!.trim()
                : widget.creatorName;
        setState(() => _currentSenderName = fallback);
      }
    }
  }

  /// Remove this swatch from Wallet (delete keep doc).
  Future<void> _unkeep() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final root = _rootId ?? widget.rootId ?? widget.swatchId;
    if (uid == null || root == null) return;

    try {
      final qs =
          await FirebaseFirestore.instance
              .collection('keeps')
              .where('userId', isEqualTo: uid)
              .where('answerId', isEqualTo: root)
              .limit(1)
              .get();
      if (qs.docs.isEmpty) return;

      await qs.docs.first.reference.delete();
      if (!mounted) return;
      setState(() {
        _isKept = false;
        _keptKnown = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Removed from Wallet')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
    }
  }

  Future<void> _loadHeartMeta(String senderId, String swatchId) async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('swatches')
              .doc(senderId)
              .collection('userSwatches')
              .doc(swatchId)
              .get();
      final d = doc.data();
      if (!mounted || d == null) return;
      setState(() {
        hearted = d['hearted'] == true;
        final name = d['heartedByName'];
        heartedByName = name is String && name.trim().isNotEmpty ? name : null;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _postSendNavTimer?.cancel(); // NEW
    _bannerController.dispose();
    _forwardMsgCtrl.dispose();
    super.dispose();
  }

  // NEW: schedule a short "success" pause, then navigate to Wallet (Sent tab).
  void _scheduleGoToSent() {
    _postSendNavTimer?.cancel();
    _postSendNavTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WalletScreen(initialTab: 2)),
        (route) => false,
      );
    });
  }

  // ------------ HEART ACTION (via REPO) ------------
  Future<void> _sendHeart() async {
    final user = FirebaseAuth.instance.currentUser;
    final myUid = user?.uid;
    final myName =
        (user?.displayName?.trim().isNotEmpty ?? false)
            ? user!.displayName!.trim()
            : 'Someone';
    final effectiveSenderId = widget.senderId ?? _resolvedSenderId;
    final swatchId = widget.swatchId;
    if (myUid == null || effectiveSenderId == null || swatchId == null) return;

    try {
      await _repo.setHeartedWithIdentity(
        senderId: effectiveSenderId,
        swatchId: swatchId,
        hearted: true,
        displayNameOverride: myName,
      );

      if (!mounted) return;
      setState(() {
        hearted = true;
        heartedByName = myName;
      });

      await showDialog<void>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Heart vibes sent'),
              content: Text(
                'Your heart vibes have been sent to '
                '${widget.creatorName.isEmpty ? "the creator" : widget.creatorName}.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send heart: $e')));
    }
  }

  Future<void> _fetchUsers() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final fetchedUsers = await UserRepository().getAllUsersExcluding(
      currentUser.uid,
    );
    if (!mounted) return;
    setState(() => users = fetchedUsers);
  }

  Future<void> _ensureUsersLoaded() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    if (users.isNotEmpty) return;
    final fetched = await UserRepository().getAllUsersExcluding(
      currentUser.uid,
    );
    if (!mounted) return;
    setState(() => users = fetched);
  }

  // ===== POPUP RECIPIENT PICKER (search + optional note) =====
  Future<void> _openRecipientPickerSheet({required bool isResendMode}) async {
    final TextEditingController searchCtrl = TextEditingController();
    final TextEditingController localNoteCtrl = TextEditingController(
      text: _forwardMsgCtrl.text,
    );
    String? tempSelection = selectedRecipientId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (users.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 12),
                    Text('Loading people...'),
                  ],
                ),
              );
            }

            final query = searchCtrl.text.trim().toLowerCase();
            final filtered =
                (query.isEmpty)
                    ? users
                    : users
                        .where(
                          (u) =>
                              u.displayName.toLowerCase().contains(query) ||
                              u.effectiveUid.toLowerCase().contains(query),
                        )
                        .toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // grabber
                  Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const Text(
                    'Choose recipient',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),

                  // Search box
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search people',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // "KEEP FOR MYSELF"
                  Builder(
                    builder: (_) {
                      final me = FirebaseAuth.instance.currentUser?.uid;
                      final isSelected = tempSelection == me && me != null;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: const CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.black87,
                            child: Icon(
                              Icons.lock,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                          title: const Text(
                            'KEEP FOR MYSELF',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onTap: () {
                            if (me != null) {
                              setSheetState(() => tempSelection = me);
                            }
                          },
                          trailing: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            size: 20,
                          ),
                        ),
                      );
                    },
                  ),

                  // Users list
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder:
                            (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFFEAEAEA),
                            ),
                        itemBuilder: (_, idx) {
                          final u = filtered[idx];
                          final selected = tempSelection == u.effectiveUid;
                          final initial =
                              (u.displayName.isNotEmpty
                                      ? u.displayName[0]
                                      : '?')
                                  .toUpperCase();

                          return InkWell(
                            onTap:
                                () => setSheetState(
                                  () => tempSelection = u.effectiveUid,
                                ),
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    selected ? const Color(0xFFF6F7F9) : null,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 4,
                              ),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFF6F72FF),
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  u.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle:
                                    isResendMode
                                        ? null
                                        : Text(
                                          u.effectiveUid,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                trailing:
                                    selected
                                        ? const Icon(
                                          Icons.check_circle,
                                          size: 20,
                                        )
                                        : const Icon(
                                          Icons.circle_outlined,
                                          size: 20,
                                        ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  if (isResendMode) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Optional note (not the original message)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: localNoteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Add a note (optional)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              (tempSelection == null)
                                  ? null
                                  : () async {
                                    if (isResendMode) {
                                      final note = localNoteCtrl.text.trim();
                                      await handleRecipientSelection(
                                        tempSelection!,
                                        messageOverride:
                                            note.isNotEmpty ? note : null,
                                      );
                                    } else {
                                      setState(() {
                                        selectedRecipientId = tempSelection;
                                      });
                                    }
                                    Navigator.pop(ctx);
                                  },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(isResendMode ? 'Send' : 'Done'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> handleRecipientSelection(
    String userId, {
    String? messageOverride,
  }) async {
    setState(() {
      isSending = true;
      selectedRecipientId = userId;
    });

    final resolvedRecipientId = await UserRepository().resolveCanonicalUid(
      userId,
    );

    final toName =
        (() {
          final match = users.cast<AppUser?>().firstWhere(
            (u) =>
                u != null &&
                (u.effectiveUid == resolvedRecipientId || u.uid == userId),
            orElse: () => null,
          );
          if (match != null && match.displayName.trim().isNotEmpty) {
            return match.displayName.trim();
          }
          final pre = widget.preselectedRecipientName?.trim();
          if (pre != null && pre.isNotEmpty) return pre;
          return resolvedRecipientId;
        })();

    try {
      final user = FirebaseAuth.instance.currentUser;
      final myUid = user?.uid;
      final myName =
          (user?.displayName?.trim().isNotEmpty ?? false)
              ? user!.displayName!.trim()
              : 'Someone';

      final effectiveSenderId = widget.senderId ?? _resolvedSenderId;
      final bool isReceived =
          (_isReceivedMeta ??
              (effectiveSenderId != null &&
                  myUid != null &&
                  effectiveSenderId != myUid &&
                  !widget.isDraft)) ==
          true;

      if (isReceived && widget.swatchId != null && effectiveSenderId != null) {
        // True forward: copy from parent path
        final parentPath =
            'swatches/$effectiveSenderId/userSwatches/${widget.swatchId}';
        await _repo.resendFromParentPath(
          parentPath: parentPath,
          toUid: resolvedRecipientId,
          toName: toName,
          messageOverride: messageOverride,
        );
      } else {
        // New send (or send of a draft)
        final swatchData = {
          'color': widget.selectedColor.value, // repo will add colorHex
          'title': widget.title,
          'message': widget.message,
          'senderName': widget.creatorName,
        };

        final bool forwardingExisting = widget.swatchId != null;
        final String? effectiveRoot =
            forwardingExisting ? (_rootId ?? widget.swatchId) : _rootId;

        String? rootCreatorId;
        String? rootCreatorName;

        if (forwardingExisting &&
            effectiveSenderId != null &&
            widget.swatchId != null) {
          try {
            // 1) Prefer parent’s embedded root creator
            final parentSnap =
                await FirebaseFirestore.instance
                    .collection('swatches')
                    .doc(effectiveSenderId)
                    .collection('userSwatches')
                    .doc(widget.swatchId!)
                    .get();
            final p = parentSnap.data();
            if (p != null) {
              rootCreatorId = (p['rootCreatorId'] as String?);
              rootCreatorName = (p['rootCreatorName'] as String?);
            }

            // 2) If missing, probe the *true root* doc via CG and use its rootCreator OR its sender as root.
            final probeId = effectiveRoot ?? widget.swatchId!;
            if ((rootCreatorId == null || rootCreatorName == null)) {
              final cg =
                  await FirebaseFirestore.instance
                      .collectionGroup('userSwatches')
                      .where(FieldPath.documentId, isEqualTo: probeId)
                      .limit(1)
                      .get();
              if (cg.docs.isNotEmpty) {
                final rd = cg.docs.first.data();
                rootCreatorId =
                    (rd['rootCreatorId'] as String?) ??
                    (rd['senderId'] as String?);
                rootCreatorName =
                    (rd['rootCreatorName'] as String?) ??
                    (rd['senderName'] as String?);
              }
            }

            // 3) Final fallback: keep previous behaviour but only as a last resort.
            if (rootCreatorId == null || rootCreatorName == null) {
              if (p != null) {
                rootCreatorId ??= (p['senderId'] as String?);
                rootCreatorName ??= (p['senderName'] as String?);
              }
            }
          } catch (_) {}
        }

        // If still unknown (e.g., first-ever send), pin to the visible creator on this screen.
        rootCreatorId ??= myUid ?? '';
        rootCreatorName ??= widget.creatorName;

        if (forwardingExisting) {
          swatchData['rootCreatorId'] = rootCreatorId;
          swatchData['rootCreatorName'] = rootCreatorName;
        }

        final newRef = await _repo.saveSwatch(
          swatchData: swatchData,
          status: 'sent',
          recipientId: resolvedRecipientId, // canonical
          rootId: effectiveRoot, // null => repo backfills to newRef.id
          parentId: widget.swatchId, // non-null only when forwarding existing
        );

        final String rootForEvent = effectiveRoot ?? newRef.id;
        final String parentForEvent =
            (forwardingExisting && widget.swatchId != null)
                ? widget.swatchId!
                : rootForEvent;

        // IMPORTANT: lineage “fromName” should be the forwarder’s display name (you), not the original creator.
        final String fromUid = myUid ?? '';
        final String fromName = myName;

        await _repo.writeLineageEvent(
          rootId: rootForEvent,
          parentId: parentForEvent,
          newId: newRef.id,
          fromUid: fromUid,
          fromName: fromName,
          toUid: resolvedRecipientId,
          toName: toName,
          rootCreatorId: rootCreatorId,
          rootCreatorName: rootCreatorName,
        );

        if (mounted) {
          setState(() {
            _rootId = effectiveRoot ?? newRef.id;
          });
        }
      }

      // NEW: increment totalSentCount for rewards after successful send
      if (myUid != null) {
        await FirebaseFirestore.instance.collection('users').doc(myUid).set({
          'totalSentCount': FieldValue.increment(1),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() {
        isSending = false;
        hasSent = true;
        sentTimestamp = DateTime.now();
        showSentBanner = true;
      });
      await _refreshKeptState(); // keep banner + kept flag in sync
      _bannerController.forward();

      // NEW: after the success banner has had a moment, jump to Wallet → Sent.
      _scheduleGoToSent();
    } catch (e) {
      if (!mounted) return;
      setState(() => isSending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send: $e')));
    }
  }

  // ---------- REPORT / BLOCK / HIDE wiring ----------
  String? _swatchPath() {
    final sid = widget.senderId ?? _resolvedSenderId;
    if (sid == null || widget.swatchId == null) return null;
    return 'swatches/$sid/userSwatches/${widget.swatchId}';
  }

  Future<String?> _promptReportDetails() async {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Report message'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Optional details (what happened?)',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Report'),
              ),
            ],
          ),
    );
  }

  Future<bool> _confirm(
    String title,
    String body, {
    String confirmLabel = 'Confirm',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
    );
    return ok == true;
  }

  Future<void> _handleMenuAction(String value) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final effectiveSenderId = widget.senderId ?? _resolvedSenderId;
    final swatchId = widget.swatchId;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need to be signed in.')),
      );
      return;
    }

    final bool isReceived =
        (_isReceivedMeta ??
                (effectiveSenderId != null && effectiveSenderId != me)) ==
            true &&
        !widget.isDraft;

    try {
      if (value == 'report') {
        final details = await _promptReportDetails();
        if (details == null) return;

        await _reportRepo.submitReport(
          reporterId: me,
          targetUserId: effectiveSenderId ?? 'unknown',
          reason: 'Abusive / Not Okay',
          swatchPath: _swatchPath(),
          details: details.isEmpty ? null : details,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report sent. Thank you.')),
        );
      } else if (value == 'block') {
        if (effectiveSenderId == null) return;
        final ok = await _confirm(
          'Block sender?',
          'You will no longer receive Zenmos from this user.',
        );
        if (!ok) return;

        await _reportRepo.setBlock(ownerUid: me, blockedUid: effectiveSenderId);

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sender blocked.')));
      } else if (value == 'report_block_delete') {
        if (effectiveSenderId == null) return;
        final details = await _promptReportDetails();
        if (details == null) return;

        await _reportRepo.submitReport(
          reporterId: me,
          targetUserId: effectiveSenderId,
          reason: 'Report + Block + Delete',
          swatchPath: _swatchPath(),
          details: details.isEmpty ? null : details,
        );

        await _reportRepo.setBlock(ownerUid: me, blockedUid: effectiveSenderId);

        if (isReceived && swatchId != null) {
          await _repo.hideForRecipient(
            senderId: effectiveSenderId,
            swatchId: swatchId,
            hidden: true,
          );
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reported, blocked, and removed.')),
        );
        if (isReceived) Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  // --- Helper: resolve a displayable recipient name for the UI hint ----------
  String? _recipientDisplayName() {
    // 1) live selection
    final sel = selectedRecipientId?.trim();
    if (sel != null && sel.isNotEmpty) {
      final match = users.cast<AppUser?>().firstWhere(
        (u) => u != null && (u.effectiveUid == sel || u.uid == sel),
        orElse: () => null,
      );
      if (match != null && match.displayName.trim().isNotEmpty) {
        return match.displayName.trim();
      }
      // could be a UID typed/prefilled
      return widget.preselectedRecipientName?.trim().isNotEmpty == true
          ? widget.preselectedRecipientName!.trim()
          : sel;
    }

    // 2) preset from caller (Create/ColorPicker)
    if (widget.preselectedRecipientName?.trim().isNotEmpty == true) {
      return widget.preselectedRecipientName!.trim();
    }
    if (widget.preselectedRecipientId?.trim().isNotEmpty == true) {
      return widget.preselectedRecipientId!.trim();
    }

    // 3) nothing chosen yet
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final effectiveSenderId = widget.senderId ?? _resolvedSenderId;
    final bool isReceived =
        (_isReceivedMeta ??
            (effectiveSenderId != null &&
                effectiveSenderId != myUid &&
                !widget.isDraft)) ??
        false;

    final bool showZenmoed = hasSent || widget.isSent;
    final DateTime? zenmoedTime =
        hasSent ? sentTimestamp : (widget.isSent ? widget.timestamp : null);

    final String zenmoedText =
        zenmoedTime == null
            ? ''
            : '${DateFormat('MMMM d, y').format(zenmoedTime)} ${DateFormat.Hms().format(zenmoedTime)}';

    final bool isCreatorViewingSent =
        widget.isSent &&
        effectiveSenderId != null &&
        effectiveSenderId == myUid;

    final bool canShowLineage = (widget.isSent || hasSent) && (_rootId != null);

    // ------- ADAPTIVE SIZING -------
    final media = MediaQuery.of(context);
    final bool isSmallPhone =
        media.size.height < 700 || media.size.shortestSide < 350;

    final double titleSize = isSmallPhone ? 24 : 30;
    final double bodySize = isSmallPhone ? 13 : 14;

    final bool showOverflowMenu =
        (widget.swatchId != null) &&
        ((_isReceivedMeta == true) ||
            ((effectiveSenderId != null) && (effectiveSenderId != myUid)));

    // Recipient hint logic (only for normal SEND flow, not re-send)
    final bool showRecipientHint =
        !hasSent && !(widget.isSent || isReceived); // about-to-send state
    final String? recipientName = _recipientDisplayName();

    // FROM name: prefer latest sender, then root creator, then creatorName, then Anonymous.
    final String fromName =
        (_currentSenderName != null && _currentSenderName!.trim().isNotEmpty)
            ? _currentSenderName!.trim()
            : (_resolvedCreatorName != null &&
                _resolvedCreatorName!.trim().isNotEmpty)
            ? _resolvedCreatorName!.trim()
            : (widget.creatorName.isNotEmpty
                ? widget.creatorName
                : 'Anonymous');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Swatch Details'),
        actions: [
          if (showOverflowMenu)
            IconButton(
              icon: const Icon(Icons.flag, color: Colors.black87),
              tooltip: 'More actions',
              onPressed: () {
                showZenmoSafetyMenu(
                  context,
                  initialLetter:
                      widget.creatorName.isNotEmpty
                          ? widget.creatorName[0]
                          : '?',
                  onReport: () => _handleMenuAction('report'),
                  onBlock: () => _handleMenuAction('block'),
                  onReportBlockDelete:
                      () => _handleMenuAction('report_block_delete'),
                );
              },
            ),
          const ZenmoMenuButton(isOnWallet: false, isOnColorPicker: false),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Divider(height: 1.0, thickness: 1.0, color: Colors.black12),
        ),
      ),
      body: Column(
        children: [
          // ======= SCROLLABLE AREA =======
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FullBleedSwatch(color: widget.selectedColor),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row + LINEAGE
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                            if (canShowLineage)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder:
                                            (_) => LineageScreen(
                                              rootId: _rootId!, // gated above
                                              swatchColor: widget.selectedColor,
                                              title: widget.title,
                                              fromName: fromName,
                                              swatchId: widget.swatchId,
                                            ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: const Size(0, 28),
                                    shape: const StadiumBorder(),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'LINEAGE',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        if (showZenmoed)
                          Text(
                            'ZENMOED: $zenmoedText',
                            style: TextStyle(fontSize: bodySize),
                          ),
                        const SizedBox(height: 2),

                        // FROM line with tiny avatar
                        Row(
                          children: [
                            // hardened avatar
                            _MiniAvatar(
                              key: Key(
                                'miniAvatar-${(widget.senderId ?? _resolvedSenderId) ?? myUid}',
                              ),
                              uid:
                                  (widget.senderId ?? _resolvedSenderId) ??
                                  myUid,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'FROM: $fromName',
                                style: TextStyle(fontSize: bodySize),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        if (widget.message.trim().isNotEmpty)
                          Text(
                            widget.message,
                            style: const TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: Colors.black87,
                              height: 1.3,
                            ),
                          ),

                        // NEW LOCATION: recipient chip (closer to buttons)
                        if (showRecipientHint && recipientName != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            decoration: const ShapeDecoration(
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: Colors.black26,
                                  width: 1,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Text(
                              'TO: $recipientName',
                              style: TextStyle(
                                fontSize: isSmallPhone ? 13 : 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],

                        if (!hasSent &&
                            widget.isDraft &&
                            !isReceived &&
                            !widget.isSent) ...[
                          const SizedBox(height: 10),
                          Center(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                shape: const CircleBorder(),
                                side: const BorderSide(color: Colors.black26),
                                padding: const EdgeInsets.all(10),
                                minimumSize: const Size(40, 40),
                              ),
                              child: const Icon(
                                Icons.edit,
                                size: 18,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),

                        if (isReceived &&
                            widget.swatchId != null &&
                            effectiveSenderId != null) ...[
                          const SizedBox(height: 10),
                          Center(
                            child: Column(
                              children: [
                                IconButton(
                                  iconSize: 28,
                                  tooltip:
                                      (hearted == true)
                                          ? 'Heart sent'
                                          : 'Send heart to creator',
                                  icon: Icon(
                                    (hearted == true)
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color:
                                        (hearted == true)
                                            ? Colors.redAccent
                                            : Colors.black45,
                                  ),
                                  onPressed:
                                      (hearted == true) ? null : _sendHeart,
                                ),
                                if (hearted == true)
                                  const Text(
                                    'Hearted',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ======= BOTTOM ACTIONS (fixed) — always show while not sent =======
          if (!hasSent)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      // LEFT BUTTON — Keep / Unkeep (with state)
                      Expanded(
                        child:
                            (_keptKnown && _isKept)
                                ? RectActionButton(
                                  icon: Icons.task_alt,
                                  label: 'Kept',
                                  subtitle: 'Remove from Wallet',
                                  onPressed: () async {
                                    await _unkeep();
                                  },
                                )
                                : RectActionButton(
                                  icon: Icons.hexagon_outlined,
                                  label: 'Keep',
                                  onPressed: () async {
                                    final wasKept = _isKept;
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => KeepsakeOptionsScreen(
                                              selectedColor:
                                                  widget.selectedColor,
                                              title: widget.title,
                                              swatchId:
                                                  widget
                                                      .swatchId, // can be null
                                              senderId: effectiveSenderId,
                                            ),
                                      ),
                                    );
                                    await _refreshKeptState();
                                    if (!wasKept && _isKept && mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Saved to Wallet'),
                                        ),
                                      );
                                    }
                                  },
                                ),
                      ),

                      const SizedBox(width: 16),

                      // RIGHT BUTTON — Send / Re-send
                      Expanded(
                        child:
                            (widget.isSent || isReceived)
                                ? RectActionButton(
                                  icon: Icons.ios_share,
                                  label: 'Reply / Re-send',
                                  subtitle: '(message does not transfer)',
                                  onPressed: () async {
                                    await _ensureUsersLoaded();
                                    await _openRecipientPickerSheet(
                                      isResendMode: true,
                                    );
                                  },
                                )
                                : RectActionButton(
                                  icon: Icons.send_outlined,
                                  label: isSending ? 'SENDING...' : 'SEND',
                                  onPressed: () async {
                                    if (isSending) return;

                                    if (selectedRecipientId == null) {
                                      await _ensureUsersLoaded();
                                      await _openRecipientPickerSheet(
                                        isResendMode: false,
                                      );
                                    }
                                    final targetId = selectedRecipientId;

                                    if (targetId == null) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Choose a recipient first',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    final msgOverride =
                                        _forwardMsgCtrl.text.trim().isNotEmpty
                                            ? _forwardMsgCtrl.text.trim()
                                            : null;

                                    handleRecipientSelection(
                                      targetId,
                                      messageOverride: msgOverride,
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (showSentBanner)
            SlideTransition(
              position: slideAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  border: Border.all(color: Colors.black87, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'Your Zenmo has been sent!',
                      style: TextStyle(fontSize: 16),
                    ),
                    Icon(Icons.rocket_launch, color: Colors.black),
                  ],
                ),
              ),
            ),

          // ======= BOTTOM NAV (fixed) =======
          SafeArea(
            top: false,
            child: Container(
              height: 60,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.black12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: () {
                      _postSendNavTimer?.cancel(); // NEW
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const WalletScreen()),
                      );
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: WalletBadgeIcon(),
                        ),
                        Text('Wallet', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      _postSendNavTimer?.cancel(); // NEW
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ColorPickerScreen(),
                        ),
                      );
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.brush, size: 24),
                        Text('Send Vibes', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  // ---- Daily Hues tab (replaces Account) ----
                  GestureDetector(
                    onTap: () {
                      _postSendNavTimer?.cancel(); // NEW
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DailyHuesScreen(),
                        ),
                      );
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.grid_view_rounded, size: 24),
                        Text('Daily Hues', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed square that sizes to the *available* width (no overlay).
class _FullBleedSwatch extends StatelessWidget {
  final Color color;
  const _FullBleedSwatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w =
            (constraints.hasBoundedWidth && constraints.maxWidth.isFinite)
                ? constraints.maxWidth
                : MediaQuery.of(context).size.width;

        return SizedBox(
          width: w,
          child: AspectRatio(aspectRatio: 1, child: ColoredBox(color: color)),
        );
      },
    );
  }
}

/// ================
/// Rect action btn
/// ================
class RectActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? subtitle;
  final VoidCallback onPressed;

  const RectActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bool isSmallPhone =
        media.size.height < 700 || media.size.shortestSide < 350;

    final double actionMinHeight = isSmallPhone ? 48 : 56;
    final double actionLabelSize = isSmallPhone ? 13 : 15;
    final double actionIconSize = isSmallPhone ? 20 : 22;
    final EdgeInsets actionPadding =
        isSmallPhone
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 12);

    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF5F6572),
        foregroundColor: Colors.white,
        padding: actionPadding,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 0,
        minimumSize: Size(0, actionMinHeight),
      ),
      icon: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Icon(icon, size: actionIconSize, color: Colors.white),
      ),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: actionLabelSize,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (subtitle != null) const SizedBox(height: 2),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isSmallPhone ? 8 : 9,
                color: Colors.white70,
                height: 1.0,
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================
// Tiny inline avatar (Review)
// ==========================
// Hardened: single avatar stream + sticky last-good + one-shot memoized fallback.
// Never reverts to checkerboard after a valid grid has been shown.
class _MiniAvatar extends StatefulWidget {
  final String? uid;
  final double size;
  const _MiniAvatar({super.key, required this.uid, this.size = 14});

  @override
  State<_MiniAvatar> createState() => _MiniAvatarState();
}

class _MiniAvatarState extends State<_MiniAvatar> {
  // Toggle debug logs if needed.
  static const bool kAvatarDebugLogs = false;

  // Sticky last-good 5x5 grid.
  final ValueNotifier<List<List<String>>?> _lastGoodGrid =
      ValueNotifier<List<List<String>>?>(null);

  // One-shot memoized fallback future.
  Future<List<List<String>>?>? _fingerprintOnce;

  String? _uidSnapshot;

  @override
  void initState() {
    super.initState();
    _uidSnapshot = widget.uid;
  }

  @override
  void didUpdateWidget(covariant _MiniAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      // Reset state if uid changed (the Key should usually prevent this).
      _uidSnapshot = widget.uid;
      _fingerprintOnce = null;
      _lastGoodGrid.value = null;
    }
  }

  @override
  void dispose() {
    _lastGoodGrid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    if (uid == null || uid.isEmpty) {
      return _buildBox(_checker());
    }

    final avatarRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('public')
        .doc('avatar');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      // Avatar stream only; we’ll ignore pending local writes.
      stream: avatarRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasData) {
          final ds = snap.data!;
          final meta = ds.metadata;
          final fromCache = meta.isFromCache;
          final pending = meta.hasPendingWrites;

          final grid = _extract5x5Grid(ds.data());

          if (kAvatarDebugLogs) {
            debugPrint(
              '[MiniAvatar] uid=$uid source=avatar exists=${ds.exists} '
              'fromCache=$fromCache pending=$pending shapeOk=${grid != null} '
              'hasLastGood=${_lastGoodGrid.value != null}',
            );
          }

          if (!pending && grid != null) {
            if (_gridsDiffer(_lastGoodGrid.value, grid)) {
              _lastGoodGrid.value = grid;
            }
          }
        }

        // If we already have a good grid, render it (never flicker back).
        final cached = _lastGoodGrid.value;
        if (cached != null) {
          return _buildBox(cached);
        }

        // No valid avatar yet -> one-shot fingerprint fallback.
        _fingerprintOnce ??= _loadFingerprintFallback(uid);
        return FutureBuilder<List<List<String>>?>(
          future: _fingerprintOnce,
          builder: (context, fp) {
            if (fp.connectionState == ConnectionState.done && fp.data != null) {
              final grid = fp.data!;
              if (_gridsDiffer(_lastGoodGrid.value, grid)) {
                _lastGoodGrid.value = grid;
              }
              return _buildBox(grid);
            }
            return _buildBox(_checker());
          },
        );
      },
    );
  }

  // ---------- Parsing & helpers ----------

  static List<List<String>>? _extract5x5Grid(Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = data['grid'];
    if (raw is! List || raw.length != 5) return null;
    final out = <List<String>>[];
    for (final row in raw) {
      if (row is! List || row.length != 5) return null;
      final casted = <String>[];
      for (final cell in row) {
        final norm = _normalizeHex(cell);
        if (norm == null) return null;
        casted.add(norm);
      }
      out.add(casted);
    }
    return out;
  }

  static String? _normalizeHex(Object? v) {
    if (v == null) return null;
    if (v is int) {
      // Treat as ARGB/RGB; keep RGB only.
      final rgb = v & 0xFFFFFF;
      return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    }
    if (v is String) {
      var s = v.trim();
      if (s.isEmpty) return null;
      if (s.startsWith('#')) s = s.substring(1);
      if (s.length == 3) {
        s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
      } else if (s.length == 8) {
        // AARRGGBB -> RRGGBB
        s = s.substring(2);
      } else if (s.length != 6) {
        return null;
      }
      final upper = s.toUpperCase();
      final isHex = RegExp(r'^[0-9A-F]{6}$').hasMatch(upper);
      if (!isHex) return null;
      return '#$upper';
    }
    return null;
  }

  Future<List<List<String>>?> _loadFingerprintFallback(String uid) async {
    try {
      final fpRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('fingerprint');

      final ds = await fpRef.get(
        const GetOptions(source: Source.serverAndCache),
      );
      if (!ds.exists) return null;

      final data = ds.data();

      List<String>? hex;
      if (data?['answersHex'] is List) {
        final raw =
            (data!['answersHex'] as List)
                .take(25)
                .map((e) => _normalizeHex(e))
                .whereType<String>()
                .toList();
        if (raw.length >= 25) hex = raw;
      }
      if (hex == null && data?['answers'] is List) {
        final raw =
            (data!['answers'] as List)
                .take(25)
                .map((e) => _normalizeHex(e))
                .whereType<String>()
                .toList();
        if (raw.length >= 25) hex = raw;
      }
      if (hex == null || hex.length < 25) return null;

      final grid = _spiral5x5(hex);
      if (kAvatarDebugLogs) {
        debugPrint('[MiniAvatar] uid=$uid source=fingerprint fallbackOK=true');
      }
      return grid;
    } catch (e) {
      if (kAvatarDebugLogs) {
        debugPrint('[MiniAvatar] uid=$uid source=fingerprint error=$e');
      }
      return null;
    }
  }

  static List<List<String>> _spiral5x5(List<String> flat25) {
    final grid = List.generate(5, (_) => List.filled(5, '#FFFFFF'));
    // Spiral order (clockwise) for 5x5.
    const order = <List<int>>[
      [0, 0],
      [0, 1],
      [0, 2],
      [0, 3],
      [0, 4],
      [1, 4],
      [2, 4],
      [3, 4],
      [4, 4],
      [4, 3],
      [4, 2],
      [4, 1],
      [4, 0],
      [3, 0],
      [2, 0],
      [1, 0],
      [1, 1],
      [1, 2],
      [1, 3],
      [2, 3],
      [3, 3],
      [3, 2],
      [3, 1],
      [2, 1],
      [2, 2],
    ];
    for (var i = 0; i < 25; i++) {
      final r = order[i][0];
      final c = order[i][1];
      grid[r][c] = flat25[i];
    }
    return grid;
  }

  static bool _gridsDiffer(List<List<String>>? a, List<List<String>> b) {
    if (a == null) return true;
    for (var r = 0; r < 5; r++) {
      for (var c = 0; c < 5; c++) {
        if (a[r][c] != b[r][c]) return true;
      }
    }
    return false;
  }

  // --- Painting ---

  Widget _buildBox(List<List<String>> grid) {
    final colors = List.generate(
      5,
      (r) => List.generate(5, (c) => _parseColor(grid[r][c])),
    );

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26, width: 0.75),
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _Grid5x5Painter(colors),
        isComplex: true,
        willChange: true,
      ),
    );
  }

  static Color _parseColor(String hex) {
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = int.parse(h, radix: 16) & 0xFFFFFF;
    return Color(0xFF000000 | value);
  }

  List<List<String>> _checker() => List.generate(
    5,
    (r) => List.generate(5, (c) => ((r + c) % 2 == 0) ? '#FFFFFF' : '#E6E8ED'),
  );
}

class _Grid5x5Painter extends CustomPainter {
  final List<List<Color>> colors;
  _Grid5x5Painter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 5.0;
    final cellH = size.height / 5.0;
    final paint = Paint();
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 5; c++) {
        paint.color = colors[r][c];
        canvas.drawRect(
          Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Grid5x5Painter oldDelegate) => true;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/swatch_repository.dart';

class WalletBadgeIcon extends StatefulWidget {
  const WalletBadgeIcon({
    super.key,
    this.selected = false, // kept for API compatibility; not used for color
    this.icon = Icons.wallet, // fallback: Icons.account_balance_wallet
    this.countStream, // optional: caller can provide combined stream
  });

  final bool selected;
  final IconData icon;
  final Stream<int>? countStream;

  @override
  State<WalletBadgeIcon> createState() => _WalletBadgeIconState();
}

class _WalletBadgeIconState extends State<WalletBadgeIcon> {
  // Use `dynamic` so this file compiles even if the repo shape changes slightly.
  dynamic _repo;

  StreamController<int>? _controller;
  StreamSubscription<int>? _subInbox;
  StreamSubscription<int>? _subKeptPending; // keeper-side unread keeps

  int _inbox = 0;
  int _keptPending = 0;

  @override
  void initState() {
    super.initState();
    _repo = SwatchRepository();

    // If parent didn't supply a countStream, we build our own:
    // badge = inboxUnread + keepsUnread (hearts deliberately excluded).
    if (widget.countStream == null) {
      _controller = StreamController<int>.broadcast();

      // Inbox stream (via SwatchRepository.inboxUnreadCountStream)
      _subInbox = _safeInboxStream().listen(
        (v) {
          _inbox = v;
          _controller?.add(_inbox + _keptPending);
        },
        onError: (_) {
          _inbox = 0;
          _controller?.add(_inbox + _keptPending);
        },
      );

      // Keeps stream (unread keeps in /keeps)
      _subKeptPending = _safeKeptPendingStream().listen(
        (v) {
          _keptPending = v;
          _controller?.add(_inbox + _keptPending);
        },
        onError: (_) {
          _keptPending = 0;
          _controller?.add(_inbox + _keptPending);
        },
      );

      // Emit an initial 0 so the badge renders promptly.
      scheduleMicrotask(() => _controller?.add(0));
    }
  }

  // Try to call repo.inboxUnreadCountStream(); fall back to a 0 stream if missing.
  Stream<int> _safeInboxStream() {
    try {
      final dynamic s = _repo.inboxUnreadCountStream();
      if (s is Stream) {
        return s.map((v) => v is int ? v : 0).handleError((Object _) {});
      }
    } catch (_) {
      /* method missing or threw */
    }
    // Fallback: a stream that immediately yields 0 and completes
    return Stream<int>.value(0);
  }

  // Count unread keeps for the current user from /keeps (readAt == null).
  Stream<int> _safeKeptPendingStream() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return Stream<int>.value(0);
      return FirebaseFirestore.instance
          .collection('keeps')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .map(
            (qs) => qs.docs.where((d) => (d.data()['readAt'] == null)).length,
          )
          .handleError((Object _) {});
    } catch (_) {
      /* defensive */
    }
    return Stream<int>.value(0);
  }

  @override
  void dispose() {
    _subInbox?.cancel();
    _subKeptPending?.cancel();
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Inherit color/size from IconTheme (so global BottomNavigationBarTheme applies)
    final it = IconTheme.of(context);
    final Color? iconColor = it.color;
    final double iconSize = it.size ?? 24.0;

    final base = Icon(
      widget.icon,
      color: iconColor, // follows theme
      size: iconSize,
    );

    // If caller supplied a stream, use it. Otherwise use our combined one.
    final Stream<int> stream = widget.countStream ?? _controller!.stream;

    return StreamBuilder<int>(
      stream: stream,
      initialData: 0,
      builder: (context, snap) {
        final int n = (snap.data ?? 0);
        if (n <= 0) return base;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            base,
            Positioned(
              right: -2,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black, // badge pill kept black for contrast
                  borderRadius: BorderRadius.circular(999),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                child: Text(
                  n > 99 ? '99+' : '$n',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

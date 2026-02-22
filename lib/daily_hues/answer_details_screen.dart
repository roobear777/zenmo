import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/answer.dart';
import '../services/keep_repository.dart';
import '../services/firestore/keep_repository_firestore.dart';

class AnswerDetailsScreen extends StatefulWidget {
  const AnswerDetailsScreen({super.key, required this.answer});

  static const routeName = '/answer';
  final Answer answer;

  @override
  State<AnswerDetailsScreen> createState() => _AnswerDetailsScreenState();
}

class _AnswerDetailsScreenState extends State<AnswerDetailsScreen> {
  final KeepRepository _keepRepo = KeepRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );

  bool _kept = false;
  bool _loadingKeep = true;

  String? _creatorName; // resolved from users/{uid} or public_feed by rootId
  bool _loadingCreator = true;

  static const String _kAnswerDeepLinkBase = 'zenmo://answer';

  @override
  void initState() {
    super.initState();
    _initKept();
    _resolveCreatorName();
  }

  Future<void> _initKept() async {
    try {
      final kept = await _keepRepo.isKept(widget.answer.id);
      if (!mounted) return;
      setState(() {
        _kept = kept;
        _loadingKeep = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingKeep = false);
    }
  }

  // Robust resolver:
  // 1) /users/{responderId}: displayName -> username -> name -> email
  // 2) fallback: /public_feed where rootId == answer.id -> creatorName
  // 3) fallback: responderId
  Future<void> _resolveCreatorName() async {
    setState(() => _loadingCreator = true);

    String? best;

    // Helper to pick first non-empty
    String pickNonEmpty(List<String?> opts, String fallback) {
      for (final s in opts) {
        if (s != null && s.trim().isNotEmpty) return s.trim();
      }
      return fallback;
    }

    // (1) users/{uid}
    try {
      final uid = widget.answer.responderId.trim();
      if (uid.isNotEmpty) {
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (snap.exists) {
          final m = (snap.data() ?? const <String, dynamic>{});
          best = pickNonEmpty([
            m['displayName'] as String?,
            m['username'] as String?,
            m['name'] as String?,
            m['email'] as String?,
          ], uid);
        } else {
          best = uid;
        }
      }
    } catch (_) {
      // ignore; will try public_feed
    }

    // (2) public_feed by rootId
    if (best == null || best.isEmpty) {
      try {
        final q =
            await FirebaseFirestore.instance
                .collection('public_feed')
                .where('rootId', isEqualTo: widget.answer.id)
                .orderBy('sentAt', descending: true)
                .limit(1)
                .get();
        if (q.docs.isNotEmpty) {
          final m = q.docs.first.data();
          final n = (m['creatorName'] as String?)?.trim();
          if (n != null && n.isNotEmpty) best = n;
        }
      } catch (_) {
        // ignore
      }
    }

    // (3) final fallback
    best ??= widget.answer.responderId.trim();

    if (!mounted) return;
    setState(() {
      _creatorName = best;
      _loadingCreator = false;
    });
  }

  Color _parseHex(String hex) {
    final s = hex.startsWith('#') ? hex.substring(1) : hex;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return const Color(0xFF000000);
    final rgb = (s.length == 8) ? (v & 0x00FFFFFF) : v; // handle AARRGGBB
    return Color(0xFF000000 | rgb);
  }

  String get _link => '$_kAnswerDeepLinkBase/${widget.answer.id}';

  String get _shareText {
    final t =
        widget.answer.title.isEmpty
            ? widget.answer.colorHex
            : widget.answer.title;
    final by =
        (_creatorName != null && _creatorName!.isNotEmpty)
            ? ' • by $_creatorName'
            : '';
    return '$t • ${widget.answer.colorHex}$by\n$_link';
  }

  Future<void> _toggleKeep() async {
    setState(() => _loadingKeep = true);
    try {
      final kept = await _keepRepo.toggleKeep(widget.answer.id);
      if (!mounted) return;
      setState(() {
        _kept = kept;
        _loadingKeep = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kept ? 'Kept to Wallet' : 'Removed from Wallet'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingKeep = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Keep failed: $e')));
    }
  }

  Future<void> _copyHex() async {
    await Clipboard.setData(ClipboardData(text: widget.answer.colorHex));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Hex copied')));
  }

  Future<void> _shareTextOnly() async {
    await Share.share(_shareText);
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(widget.answer.colorHex);
    final title =
        widget.answer.title.isEmpty
            ? widget.answer.colorHex
            : widget.answer.title;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swatch Details'),
        actions: [
          IconButton(
            tooltip: 'Copy hex',
            icon: const Icon(Icons.copy),
            onPressed: _copyHex,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share),
            onPressed: _shareTextOnly,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Divider(height: 1.0, thickness: 1.0, color: Colors.black12),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FullBleedSwatch(color: color),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.answer.colorHex,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (!_loadingCreator &&
                        _creatorName != null &&
                        _creatorName!.isNotEmpty)
                      Text(
                        'by $_creatorName',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                12 + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _loadingKeep ? null : _toggleKeep,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            elevation: 0,
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                          icon: Icon(
                            _kept ? Icons.bookmark : Icons.bookmark_border,
                          ),
                          label: Text(_kept ? 'Unkeep' : 'Keep'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyHex,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          icon: const Icon(Icons.copy_all),
                          label: const Text('Copy Hex'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _shareTextOnly,
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Link: $_link',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/swatch_repository.dart';

class LineageScreen extends StatefulWidget {
  final String rootId;
  final Color swatchColor;
  final String title;
  final String fromName; // legacy fallback if events lack root creator
  final String? swatchId;

  const LineageScreen({
    super.key,
    required this.rootId,
    required this.swatchColor,
    required this.title,
    required this.fromName,
    this.swatchId,
  });

  @override
  State<LineageScreen> createState() => _LineageScreenState();
}

class _LineageScreenState extends State<LineageScreen> {
  final _repo = SwatchRepository();
  bool _loading = true;

  /// Events ordered ASC by sentAt (as returned by repo)
  List<Map<String, dynamic>> _eventsAsc = [];

  /// True creator for the root family (stable across resends)
  String? _creatorName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await _repo.getLineage(widget.rootId); // ASC

      // Enrich with `kept` by peeking the *owner/sender* doc for each hop.
      final futures = <Future<void>>[];
      for (final e in events) {
        if (e['kept'] is bool) continue;
        final ownerUid = e['fromUid'] as String?;
        final newId = e['newId'] as String?;
        if (ownerUid == null || newId == null) continue;

        futures.add(
          FirebaseFirestore.instance
              .collection('swatches')
              .doc(ownerUid) // sender owns the doc
              .collection('userSwatches')
              .doc(newId)
              .get()
              .then((doc) {
                final data = doc.data();
                if (data != null && data['kept'] is bool) {
                  e['kept'] = data['kept'] as bool;
                }
              })
              .catchError((_) {}),
        );
      }
      await Future.wait(futures);

      // Derive creator:
      // 1) first non-null rootCreatorName anywhere in the list,
      // 2) else earliest event.fromName,
      // 3) else widget.fromName.
      String? creator;
      if (events.isNotEmpty) {
        for (final e in events) {
          final rc = (e['rootCreatorName'] as String?)?.trim();
          if (rc != null && rc.isNotEmpty) {
            creator = rc;
            break;
          }
        }
        creator ??= (events.first['fromName'] as String?);
      }
      creator ??= widget.fromName;

      if (!mounted) return;
      setState(() {
        _eventsAsc = events;
        _creatorName = creator;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not load lineage')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMMM d, y');

    // Display recipients newest-first for readability
    final eventsDesc = _eventsAsc.reversed.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Swatch Lineage')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header swatch card
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: widget.swatchColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'FROM: ${_creatorName ?? widget.fromName}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              'Past recipients',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (eventsDesc.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No lineage events yet.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else ...[
              for (final e in eventsDesc) _RecipientTile(e: e, df: df),

              // Dedicated CREATOR row (never mislabels a recipient)
              const SizedBox(height: 8),
              _CreatorTile(name: _creatorName ?? widget.fromName),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({required this.e, required this.df});

  final Map<String, dynamic> e;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final String toName = (e['toName'] as String?) ?? 'Unknown';
    final Timestamp? ts = e['sentAt'] as Timestamp?;
    final String date = ts == null ? '' : df.format(ts.toDate());
    final bool kept = e['kept'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFECEFF1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.person, size: 18, color: Colors.black54),
        ),
        title: Text(
          toName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          date.isEmpty ? 'SENT' : 'SENT $date',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        trailing:
            kept
                ? const Icon(Icons.hexagon, size: 18, color: Colors.black54)
                : null,
      ),
    );
  }
}

class _CreatorTile extends StatelessWidget {
  const _CreatorTile({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: const ListTileTheme(
        data: ListTileThemeData(dense: true),
        child: SizedBox.shrink(),
      ),
    ).copyWithChild(
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFECEFF1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.person, size: 18, color: Colors.black54),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text(
          'CREATOR',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        trailing: const Icon(
          Icons.local_florist,
          size: 18,
          color: Colors.black54,
        ),
      ),
    );
  }
}

// Small helper to keep the Container styling but replace its child with a ListTile
extension on Widget {
  Widget copyWithChild(Widget child) {
    if (this is Container) {
      final c = this as Container;
      return Container(
        margin: c.margin,
        padding: c.padding,
        decoration: c.decoration,
        foregroundDecoration: c.foregroundDecoration,
        constraints: c.constraints,
        transform: c.transform,
        transformAlignment: c.transformAlignment,
        clipBehavior: c.clipBehavior,
        child: child,
      );
    }
    return child;
  }
}

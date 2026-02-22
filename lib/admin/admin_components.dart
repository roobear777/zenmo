import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// ---------------------------------------------------------------------------
/// Admin theme tokens (neutral grays)
/// ---------------------------------------------------------------------------
const Color kAdminText = Color(0xFF1F2937); // gray-800
const Color kAdminMuted = Color(0xFF6B7280); // gray-500
const Color kAdminBorder = Color(0xFFE5E7EB); // gray-200
const Color kAdminDivider = Color(0xFFE5E7EB);
const Color kAdminChipBg = Color(0xFFF9FAFB); // gray-50

/// Shared “wide mode” flag the dashboard sets while it’s on screen.
final ValueNotifier<bool> adminIsWide = ValueNotifier<bool>(false);

/// Clipboard + feedback helper for admin actions.
Future<void> adminCopyToClipboard(
  BuildContext context,
  String text, {
  String? successMessage,
}) async {
  if (text.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Nothing to copy')));
    return;
  }
  await Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(successMessage ?? 'Copied to clipboard')),
  );
}

// ---------------------------------------------------------------------------
// Reusable UI components
// ---------------------------------------------------------------------------

class AdminFiltersBar extends StatelessWidget {
  const AdminFiltersBar({
    super.key,
    required this.rangeLabel,
    required this.rangeSegments,
    required this.selectedValue,
    required this.onRangeChanged,
    required this.onRefresh,
  });

  final String rangeLabel;
  final List<ButtonSegment<dynamic>> rangeSegments;
  final dynamic selectedValue;
  final void Function(dynamic) onRangeChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const SizedBox(width: 4),
            SegmentedButton<dynamic>(
              segments: rangeSegments,
              selected: {selectedValue},
              onSelectionChanged: (s) => onRangeChanged(s.first),
            ),
            const SizedBox(width: 12),
            Text('Range: $rangeLabel'),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminEnvChip extends StatelessWidget {
  const AdminEnvChip({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      label: Text(label),
    );
  }
}

class AdminSearchBox extends StatelessWidget {
  const AdminSearchBox({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.hintText = 'Search by UID or HEX',
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        prefixIcon: const Icon(Icons.search),
        hintText: hintText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onSubmitted: onSubmit,
    );
  }
}

class AdminKpiCard extends StatelessWidget {
  const AdminKpiCard({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        width: 180,
        height: 84,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const Spacer(),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminTableHeaderRow extends StatelessWidget {
  const AdminTableHeaderRow({super.key, required this.cells});
  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 40), // leading slot
          ...cells.map(
            (c) => Expanded(
              child: Text(
                c,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminTableRow extends StatelessWidget {
  const AdminTableRow({super.key, required this.cells, required this.leading});
  final List<String> cells;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 40, child: Center(child: leading)),
          ...cells.map((c) => Expanded(child: Text(c))),
        ],
      ),
    );
  }
}

class AdminColorChip extends StatelessWidget {
  const AdminColorChip(this.hex, {super.key});
  final String hex;

  @override
  Widget build(BuildContext context) {
    final color = adminColorFromHex(hex);
    return Tooltip(
      message: hex,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class AdminColorStrip extends StatelessWidget {
  const AdminColorStrip({super.key, required this.colors});
  final List<String> colors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: colors.map((h) => AdminColorChip(h)).toList(),
    );
  }
}

class AdminHueHistogram extends StatelessWidget {
  const AdminHueHistogram({super.key, required this.hexCounts});
  final Map<String, int> hexCounts; // may be hex->count or Hbin->count

  @override
  Widget build(BuildContext context) {
    final Map<String, int> bins = {};
    if (hexCounts.isNotEmpty && hexCounts.keys.first.startsWith('#')) {
      hexCounts.forEach((hex, c) {
        final key = adminHueBinKey(hex);
        bins[key] = (bins[key] ?? 0) + c;
      });
    } else {
      bins.addAll(hexCounts);
    }

    final entries =
        bins.entries.toList()
          ..sort((a, b) => _binIndex(a.key).compareTo(_binIndex(b.key)));
    final maxV = entries.fold<int>(1, (m, e) => math.max(m, e.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children:
                entries.map((e) {
                  final ratio = e.value / maxV;
                  final height = 16 + 90 * ratio;
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(height: height, color: Colors.teal.shade200),
                        const SizedBox(height: 4),
                        Text(e.key, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  );
                }).toList(),
          ),
        ),
      ),
    );
  }

  static int _binIndex(String k) => int.tryParse(k.replaceAll('H', '')) ?? 0;
}

class AdminSvHeatmap extends StatelessWidget {
  const AdminSvHeatmap({super.key, required this.bins});
  final List<List<int>> bins; // 4x4 [s][v]

  @override
  Widget build(BuildContext context) {
    int maxV = 1;
    for (final row in bins) {
      for (final v in row) {
        if (v > maxV) maxV = v;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('S × V heatmap'),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: List.generate(4, (s) {
                    return Expanded(
                      child: Column(
                        children: List.generate(4, (v) {
                          final val = bins[s][v];
                          final ratio = val / maxV;
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(
                                  0.15 + 0.7 * ratio,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Text(
                                '$val',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Utilities (HEX/HSV helpers, search validators, doc time helper)
// ---------------------------------------------------------------------------

bool adminLooksLikeHex(String s) {
  final t = s.trim();
  final r = RegExp(r'^#?[0-9A-Fa-f]{6}$');
  return r.hasMatch(t);
}

bool adminLooksLikeUid(String s) {
  // Keep permissive: typical Firebase UID ~28 chars.
  return s.length >= 20 && s.length <= 36 && !s.contains(' ');
}

String adminNormalizeHex(String s) {
  var t = s.trim().toUpperCase();
  if (!t.startsWith('#')) t = '#$t';
  return t;
}

Color adminColorFromHex(String hex) {
  final h = adminNormalizeHex(hex).substring(1);
  final v = int.tryParse(h, radix: 16) ?? 0;
  return Color(0xFF000000 | v);
}

String adminHueBinKey(String hex) {
  final hsv = adminHexToHsv(adminNormalizeHex(hex));
  final bin = (hsv.h / 30).floor().clamp(0, 11); // 12 bins
  return 'H$bin';
}

List<List<int>> adminSvBinsFromHexList(List<String> hexes) {
  final bins = List.generate(4, (_) => List.filled(4, 0));
  for (final hex in hexes) {
    final hsv = adminHexToHsv(adminNormalizeHex(hex));
    final sBin = (hsv.s * 4).floor().clamp(0, 3);
    final vBin = (hsv.v * 4).floor().clamp(0, 3);
    bins[sBin][vBin]++;
  }
  return bins;
}

List<List<int>> adminSvBinsFromHexes(Map<String, int> hexCounts) {
  final bins = List.generate(4, (_) => List.filled(4, 0));
  hexCounts.forEach((hex, c) {
    final hsv = adminHexToHsv(adminNormalizeHex(hex));
    final sBin = (hsv.s * 4).floor().clamp(0, 3);
    final vBin = (hsv.v * 4).floor().clamp(0, 3);
    bins[sBin][vBin] += c;
  });
  return bins;
}

class AdminHSV {
  final double h, s, v;
  const AdminHSV(this.h, this.s, this.v);
}

AdminHSV adminHexToHsv(String hex) {
  final color = adminColorFromHex(hex);
  final r = color.red / 255.0;
  final g = color.green / 255.0;
  final b = color.blue / 255.0;
  final maxC = math.max(r, math.max(g, b));
  final minC = math.min(r, math.min(g, b));
  final delta = maxC - minC;

  double h;
  if (delta == 0) {
    h = 0;
  } else if (maxC == r) {
    h = 60 * (((g - b) / delta) % 6);
  } else if (maxC == g) {
    h = 60 * (((b - r) / delta) + 2);
  } else {
    h = 60 * (((r - g) / delta) + 4);
  }
  if (h < 0) h += 360.0;

  final v = maxC;
  final double s = maxC == 0 ? 0.0 : (delta / maxC);

  return AdminHSV(h, s, v);
}

/// For mixed sent/draft docs, pick the correct timestamp.
Timestamp? adminDocTime(QueryDocumentSnapshot<Map<String, dynamic>> d) {
  final m = d.data();
  if ((m['status'] ?? 'draft') == 'sent') {
    return m['sentAt'] as Timestamp?;
  }
  return m['createdAt'] as Timestamp?;
}

/// ---------------------------------------------------------------------------
/// AdminNameCache — resolve usernames/display names/emails for UIDs
/// ---------------------------------------------------------------------------
/// Usage:
///   final cache = AdminNameCache(db);
///   final names = await cache.resolve({'uidA','uidB'});
///   final label = cache.nameFor('uidA'); // username > displayName > email > uid
class AdminNameCache {
  AdminNameCache(this.db);
  final FirebaseFirestore db;
  final Map<String, String> _cache = {};

  /// Resolve display labels for the given UIDs.
  /// Fallback order: username > displayName > email > uid.
  Future<Map<String, String>> resolve(Iterable<String> uids) async {
    // Filter to only what we still need.
    final need = <String>{
      for (final u in uids)
        if (u.isNotEmpty && !_cache.containsKey(u)) u,
    };

    // Firestore whereIn supports up to 10 values; chunk accordingly.
    while (need.isNotEmpty) {
      final chunk = need.take(10).toList();
      need.removeAll(chunk);

      final qs =
          await db
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

      for (final d in qs.docs) {
        final m = d.data();
        final username = (m['username'] ?? '') as String;
        final display = (m['displayName'] ?? '') as String;
        final email = (m['email'] ?? '') as String;
        _cache[d.id] =
            username.isNotEmpty
                ? username
                : (display.isNotEmpty
                    ? display
                    : (email.isNotEmpty ? email : d.id));
      }

      // Any truly missing docs: fall back to raw UID.
      for (final id in chunk) {
        _cache.putIfAbsent(id, () => id);
      }
    }

    return {for (final u in uids) u: _cache[u] ?? u};
  }

  /// Returns the resolved label if known, else the uid itself.
  String nameFor(String uid) => _cache[uid] ?? uid;
}

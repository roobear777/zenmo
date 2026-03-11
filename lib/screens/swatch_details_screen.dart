import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/color_swatch.dart' as models;
import '../widgets/navigation_button.dart';

/// Swatch details screen displaying full details of a saved color
/// Requirements: 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8, 9.9, 9.10, 9.11, 9.12, 10.1, 10.2, 10.3, 10.4
class SwatchDetailsScreen extends StatelessWidget {
  final models.ColorSwatch swatch;

  const SwatchDetailsScreen({
    super.key,
    required this.swatch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top bar with back button and title
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // Back button - Requirement 9.2
                  NavigationButton(
                    type: NavigationButtonType.back,
                    onPressed: () {
                      // Close modal - Requirement 9.11
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 16),
                  // "Swatch Details" title - Requirement 9.3
                  const Text(
                    'Swatch Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),

                    // Large color display - Requirement 9.4
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: swatch.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Color title - Requirement 9.5
                    Text(
                      swatch.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Created date and creator info in purple box - Requirement 9.6
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Created: ${DateFormat('MMM d, yyyy').format(swatch.createdAt)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                size: 16,
                                color: Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Creator: ${swatch.creator}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.palette,
                                size: 16,
                                color: Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Hex: ${swatch.hexValue}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Note text (if provided) - Requirement 9.7
                    if (swatch.note != null && swatch.note!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Note to Self',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              swatch.note!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // "Keepsake" button - Requirement 9.8
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          // Placeholder for keepsake functionality
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Keepsake feature coming soon!'),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Keepsake',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // "Share" button - Requirement 9.9, 10.1
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => _shareColor(context),
                        icon: const Icon(Icons.share),
                        label: const Text(
                          'Share',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Home button at bottom - Requirement 9.10
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: NavigationButton(
                type: NavigationButtonType.home,
                onPressed: () {
                  // Navigate to InitialLogoScreen - Requirement 9.12
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Share the color swatch
  /// Requirements: 10.1, 10.2, 10.3, 10.4
  void _shareColor(BuildContext context) {
    // Format share content - Requirement 10.2, 10.4
    final shareText = StringBuffer();
    shareText.writeln(swatch.title);
    shareText.writeln(swatch.hexValue);
    if (swatch.note != null && swatch.note!.trim().isNotEmpty) {
      shareText.writeln(swatch.note);
    }

    // Trigger native platform share sheet - Requirement 10.1, 10.3
    Share.share(
      shareText.toString(),
      subject: swatch.title,
    );
  }
}

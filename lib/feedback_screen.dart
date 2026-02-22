import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Full-page feedback form used from App Info.
/// - Rating (1–5) is REQUIRED.
/// - All text fields are optional.
/// - “Robotness” is just for fun.
/// - Optional single file (image/video) is base64’d and posted with the form.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  // --- Configure destination (Apps Script webhook) --------------------------
  static const String _MAIL_ENDPOINT =
      'https://script.google.com/macros/s/AKfycbyKzhzn5v4gfqyY8Ix_o_G6z7VpRS5xg2Bi4vY_b9cGo92BeFGDX-xqzAR9DJYVMXo6/exec';
  static const String _MAIL_TOKEN =
      'a3f7c1b9e0d4420dbf0d0c7e4c9f2f8a6d11b5e3f87e0b12c4d5a6b7c8d9e0f1';

  // --- Form state -----------------------------------------------------------
  int _rating = 0; // REQUIRED
  bool _robot = true; // for fun

  final _likeCtrl = TextEditingController();
  final _wishCtrl = TextEditingController();
  final _wonderCtrl = TextEditingController();
  final _extraCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  PlatformFile? _picked; // optional single file
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    final email = u?.email?.trim();
    if (email != null && email.isNotEmpty) {
      _emailCtrl.text = email;
    }
  }

  @override
  void dispose() {
    _likeCtrl.dispose();
    _wishCtrl.dispose();
    _wonderCtrl.dispose();
    _extraCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true, // ensures bytes are populated on all platforms
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
        'mp4',
        'mov',
        'webm',
        'avi',
        'mkv',
      ],
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() => _picked = res.files.first);
    }
  }

  Future<void> _submit() async {
    if (_rating <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a star rating (1–5).')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final u = FirebaseAuth.instance.currentUser;
      final displayName =
          (u?.displayName?.trim().isNotEmpty ?? false)
              ? u!.displayName!.trim()
              : (u?.email ?? 'anonymous');
      final uid = u?.uid ?? '(signed out)';

      // Build human-readable body text (for your email/Sheet)
      final bodyLines = <String>[
        'Feedback for current release',
        'Rating: $_rating / 5',
        'Robotness: ${_robot ? "I am a robot" : "I am NOT a robot"}',
        if (_likeCtrl.text.trim().isNotEmpty)
          '\nI like:\n${_likeCtrl.text.trim()}',
        if (_wishCtrl.text.trim().isNotEmpty)
          '\nI wish:\n${_wishCtrl.text.trim()}',
        if (_wonderCtrl.text.trim().isNotEmpty)
          '\nI wonder:\n${_wonderCtrl.text.trim()}',
        if (_extraCtrl.text.trim().isNotEmpty)
          '\nAnything else:\n${_extraCtrl.text.trim()}',
        '\n—',
        'From: $displayName',
        'UID: $uid',
        'Email (optional field): ${_emailCtrl.text.trim().isEmpty ? "(none)" : _emailCtrl.text.trim()}',
        'Device time: ${DateTime.now().toIso8601String()}',
        if (kIsWeb) 'Platform: Web' else 'Platform: Mobile/Desktop',
      ];
      final body = bodyLines.join('\n');

      // Encode optional file (small screenshots/videos recommended)
      String? fileName;
      String? fileMime;
      String? fileB64;

      if (_picked != null && _picked!.bytes != null) {
        final Uint8List bytes = _picked!.bytes!;
        fileName = _picked!.name;
        // naive mime guess:
        if (_picked!.extension != null) {
          final ext = _picked!.extension!.toLowerCase();
          if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
            fileMime = 'image/$ext'.replaceAll('jpg', 'jpeg');
          } else if (['mp4', 'mov', 'webm', 'avi', 'mkv'].contains(ext)) {
            // broad default; server side can refine
            fileMime = 'video/$ext';
          }
        }
        fileB64 = base64Encode(bytes);
      }

      // Single POST; server can detect presence of file fields.
      final form = <String, String>{
        'token': _MAIL_TOKEN,
        'subject': 'Zenmo App Feedback (rating: $_rating)',
        'body': body,
        if (_emailCtrl.text.trim().isNotEmpty)
          'replyTo': _emailCtrl.text.trim(),
        if (fileName != null) 'fileName': fileName,
        if (fileMime != null) 'fileMime': fileMime,
        if (fileB64 != null) 'fileB64': fileB64,
      };

      final res = await http.post(
        Uri.parse(_MAIL_ENDPOINT),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: form.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
      );

      if (res.statusCode >= 400) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      try {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        if (json['ok'] != true) {
          throw Exception('Script error: ${json['error'] ?? 'unknown'}');
        }
      } catch (_) {
        // If Apps Script returns non-JSON "OK", tolerate it.
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Thanks! Feedback sent.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn’t send feedback: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF17D6CF); // accent like your mock

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Zenmo Feedback'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.black12),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'On a scale of 1–5, I rate this current release of the app:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),

            // Stars
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: List.generate(5, (i) {
                final idx = i + 1;
                final filled = _rating >= idx;
                return IconButton(
                  splashRadius: 22,
                  onPressed: () => setState(() => _rating = idx),
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 32,
                    color: teal,
                  ),
                );
              }),
            ),

            const SizedBox(height: 16),
            _Label('I like...'),
            _Box(controller: _likeCtrl),

            const SizedBox(height: 16),
            _Label('I wish...'),
            _Box(controller: _wishCtrl),

            const SizedBox(height: 16),
            _Label('I wonder...'),
            _Box(controller: _wonderCtrl),

            const SizedBox(height: 16),
            _Label('Anything else?'),
            _Box(controller: _extraCtrl),

            const SizedBox(height: 20),
            _Label('Wanna share a screenshot or video?'),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.add),
                  label: const Text('Upload File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _picked == null ? 'No file selected' : _picked!.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            _Label('Your email address (optional):'),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'name@example.com',
                fillColor: Colors.white,
                filled: true,
              ),
            ),

            const SizedBox(height: 20),
            _Label('Robotness?'),
            Column(
              children: [
                RadioListTile<bool>(
                  value: true,
                  groupValue: _robot,
                  onChanged: (v) => setState(() => _robot = v ?? true),
                  title: const Text('I am a robot'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: teal,
                ),
                RadioListTile<bool>(
                  value: false,
                  groupValue: _robot,
                  onChanged: (v) => setState(() => _robot = v ?? false),
                  title: const Text('I am NOT a robot'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: teal,
                ),
              ],
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child:
                    _submitting
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text(
                          'Submit',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Small UI bits -----------------------------------------------------------

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}

class _Box extends StatelessWidget {
  final TextEditingController controller;
  const _Box({required this.controller});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(
        hintText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(),
        isDense: false,
      ),
    );
  }
}

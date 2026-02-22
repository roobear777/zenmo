import 'package:color_wallet/widgets/wallet_badge_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';

import '../services/swatch_repository.dart';
import '../services/user_identity_service.dart';
import '../services/user_repository.dart';
import 'review_screen.dart';
import 'wallet_screen.dart';
import 'daily_hues/daily_hues_screen.dart';

const List<String> _emojiChoices = [
  '😀',
  '😁',
  '😂',
  '🤣',
  '😅',
  '😊',
  '😇',
  '🙂',
  '🙃',
  '😉',
  '😍',
  '😘',
  '😜',
  '🤗',
  '🤩',
  '🤔',
  '😐',
  '😑',
  '😶',
  '🙄',
  '😏',
  '😴',
  '🤤',
  '😮',
  '😳',
  '🥰',
  '🤪',
  '🥳',
  '😭',
  '😡',
  '😤',
  '❤️',
];

class CreateScreen extends StatefulWidget {
  final Color selectedColor;

  /// Passed from ColorPickerScreen after the user chose a recipient there.
  final String? presetRecipientId;
  final String? presetRecipientName;

  const CreateScreen({
    super.key,
    required this.selectedColor,
    this.presetRecipientId,
    this.presetRecipientName,
  });

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _messageFocusNode = FocusNode();

  final _swatchRepo = SwatchRepository();
  final _identitySvc = UserIdentityService();
  String? displayName;

  // recipient data (local to CreateScreen)
  final _userRepo = UserRepository();
  List<AppUser> _users = [];
  bool _loadingUsers = true;
  String? _selectedRecipientId;
  String? _selectedRecipientName;

  // --- bottom nav wiring ---
  final int _selectedIndex = 1; // Create tab

  void _onNavTapped(int index) {
    if (index == _selectedIndex) return;
    if (index == 0) {
      Navigator.of(context, rootNavigator: false).pushReplacement(
        MaterialPageRoute(builder: (_) => const WalletScreen()),
      );
    } else if (index == 2) {
      Navigator.of(context, rootNavigator: false).pushReplacement(
        MaterialPageRoute(builder: (_) => const DailyHuesScreen()),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    // Seed selected recipient with any preset (e.g. from ColorPicker)
    _selectedRecipientId = widget.presetRecipientId;
    _selectedRecipientName = widget.presetRecipientName;

    _identitySvc.getDisplayName().then((name) {
      if (!mounted) return;
      setState(() => displayName = name);
    });

    _loadRecipients();
  }

  Future<void> _loadRecipients() async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      if (me == null) {
        setState(() {
          _users = [];
          _loadingUsers = false;
        });
        return;
      }
      final list = await _userRepo.getAllUsersExcluding(me.uid);
      if (!mounted) return;
      setState(() {
        _users = list;
        _loadingUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _users = [];
        _loadingUsers = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _titleFocusNode.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildSwatchData() {
    return {
      'color': widget.selectedColor.value,
      'title': _titleController.text.trim(),
      'message': _messageController.text.trim(),
      'senderName': displayName,
    };
  }

  Future<void> _saveAsDraft() async {
    if (displayName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for name to load')),
      );
      return;
    }

    try {
      await _swatchRepo.saveSwatch(
        swatchData: _buildSwatchData(),
        status: 'draft',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Draft saved')));

      Navigator.of(context, rootNavigator: false).pushReplacement(
        MaterialPageRoute(builder: (_) => const WalletScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save draft: $e')));
    }
  }

  Future<void> _openRecipientSheet() async {
    final picked = await showModalBottomSheet<_CreatePickedRecipient>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) => _CreateRecipientPickerSheet(
            users: _users,
            loading: _loadingUsers,
          ),
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedRecipientId = picked.id;
        _selectedRecipientName = picked.name;
      });
    }
  }

  Future<void> _continueToReview() async {
    if (_titleController.text.trim().isEmpty || displayName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title and wait for loading'),
        ),
      );
      return;
    }

    // Make sure a recipient is chosen on this screen.
    if (_selectedRecipientId == null) {
      await _openRecipientSheet();
      if (_selectedRecipientId == null) {
        return;
      }
    }

    final String recipientId = _selectedRecipientId!;
    final String recipientName =
        _selectedRecipientName ?? _selectedRecipientId!;

    Navigator.of(context, rootNavigator: false).push(
      MaterialPageRoute(
        builder:
            (context) => ReviewScreen(
              selectedColor: widget.selectedColor,
              title: _titleController.text,
              message: _messageController.text,
              creatorName: displayName!,
              timestamp: DateTime.now(),

              // We already chose a recipient here.
              showRecipientDropdown: false,
              preselectedRecipientId: recipientId,
              preselectedRecipientName: recipientName,
              isDraft: false,
            ),
      ),
    );
  }

  void _insertEmoji(TextEditingController controller, String emoji) {
    final text = controller.text;
    final selection = controller.selection;
    final int start = selection.start >= 0 ? selection.start : text.length;
    final int end = selection.end >= 0 ? selection.end : text.length;

    final newText = text.replaceRange(start, end, emoji);
    controller.value = controller.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _openEmojiPicker(
    TextEditingController controller,
    FocusNode focusNode,
  ) async {
    if (!kIsWeb) return;

    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Insert emoji',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    itemCount: _emojiChoices.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemBuilder: (_, i) {
                      final emoji = _emojiChoices[i];
                      return InkWell(
                        onTap: () => Navigator.of(ctx).pop(emoji),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosen != null) {
      _insertEmoji(controller, chosen);
    }

    // Restore focus to the field after closing the picker
    FocusScope.of(context).requestFocus(focusNode);
  }

  @override
  Widget build(BuildContext context) {
    const double horizontalPadding = 16.0;
    const labelStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);

    // Big, responsive square swatch
    Widget buildResponsiveSwatch(Color color) {
      return LayoutBuilder(
        builder: (context, cons) {
          final w = cons.maxWidth;
          final h = cons.maxHeight;
          final sideFromWidth = w * 0.82;
          final sideFromHeight = h * 0.46;
          final side = math.min(sideFromWidth, sideFromHeight);
          final clamped = side.clamp(180.0, 460.0);

          return Center(
            child: Container(
              width: clamped,
              height: clamped,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameH = constraints.maxHeight;

        int messageLines = 3;
        double btnH = 46;

        if (frameH >= 840) {
          messageLines = 4;
          btnH = 46;
        } else if (frameH >= 740) {
          messageLines = 3;
          btnH = 46;
        } else if (frameH >= 660) {
          messageLines = 3;
          btnH = 44;
        } else {
          messageLines = 2;
          btnH = 44;
        }

        final bool tight = frameH < 600;
        final double topGap = tight ? 8 : 12;
        final double betweenGap1 = tight ? 10 : 14;
        final double betweenGap2 = tight ? 8 : 12;

        final double kb = MediaQuery.of(context).viewInsets.bottom;
        // Equal-margin positioning: reserve the same space below and above the buttons
        final double bottomReserve =
            12 +
            MediaQuery.of(context).viewPadding.bottom +
            kBottomNavigationBarHeight;

        final contentColumn = Padding(
          padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.max,
            children: [
              SizedBox(height: topGap),

              buildResponsiveSwatch(widget.selectedColor),

              SizedBox(height: betweenGap1),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Color Name', style: labelStyle),
                  if (kIsWeb)
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Insert emoji',
                      onPressed:
                          () => _openEmojiPicker(
                            _titleController,
                            _titleFocusNode,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                maxLength: 25,
                scrollPadding: EdgeInsets.only(bottom: kb + 120),
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  hintText: '{25 characters}',
                  hintStyle: TextStyle(fontSize: 14),
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                textInputAction: TextInputAction.next,
              ),

              SizedBox(height: betweenGap2),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Optional Message', style: labelStyle),
                  if (kIsWeb)
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Insert emoji',
                      onPressed:
                          () => _openEmojiPicker(
                            _messageController,
                            _messageFocusNode,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                scrollPadding: EdgeInsets.only(bottom: kb + 120),
                maxLines: messageLines,
                maxLength: 150,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  hintText: '{150 characters}',
                  hintStyle: TextStyle(fontSize: 14),
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),

              const SizedBox(height: 16),

              // Equal top gap so the buttons sit halfway to the nav bar
              SizedBox(height: bottomReserve),

              // Buttons pinned to bottom; respect keyboard inset
              AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(bottom: kb > 0 ? kb : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _continueToReview,
                            icon: const Icon(Icons.check_circle, size: 16),
                            label: Text(
                              _selectedRecipientId == null
                                  ? 'Choose recipient'
                                  : 'Review & Send',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5F6572),
                              foregroundColor: Colors.white,
                              minimumSize: Size(0, btnH),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saveAsDraft,
                            icon: const Icon(Icons.save_outlined, size: 16),
                            label: const Text('Save to Drafts'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5F6572),
                              foregroundColor: Colors.white,
                              minimumSize: Size(0, btnH),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Equal bottom gap down to the nav bar
                    SizedBox(height: bottomReserve),
                  ],
                ),
              ),
            ],
          ),
        );

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 1,
            title: const Text(
              'Color Creation',
              style: TextStyle(color: Colors.black),
            ),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed:
                  () => Navigator.of(context, rootNavigator: false).pop(),
            ),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, thickness: 1, color: Colors.black26),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              // grows when the keyboard shows, giving room to scroll fields up
              padding: EdgeInsets.only(bottom: kb + 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : 0,
                ),
                child: contentColumn,
              ),
            ),
          ),
          // Bottom nav: Daily Hues on the right
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onNavTapped,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
            ),
            items: const [
              BottomNavigationBarItem(icon: WalletBadgeIcon(), label: 'Wallet'),
              BottomNavigationBarItem(
                icon: Icon(Icons.brush),
                label: 'Send Vibes',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.grid_view_rounded),
                label: 'Daily Hues',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------- CreateScreen recipient sheet ----------

class _CreatePickedRecipient {
  final String id;
  final String name;
  const _CreatePickedRecipient({required this.id, required this.name});
}

class _CreateRecipientPickerSheet extends StatefulWidget {
  final List<AppUser> users;
  final bool loading;
  const _CreateRecipientPickerSheet({
    required this.users,
    required this.loading,
  });

  @override
  State<_CreateRecipientPickerSheet> createState() =>
      _CreateRecipientPickerSheetState();
}

class _CreateRecipientPickerSheetState
    extends State<_CreateRecipientPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lower = _query.toLowerCase();
    final filtered =
        widget.users.where((u) {
          final name = u.displayName.toLowerCase();
          final id = (u.effectiveUid ?? u.uid).toLowerCase();
          return lower.isEmpty || name.contains(lower) || id.contains(lower);
        }).toList();

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: widget.users.isNotEmpty,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search people',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                widget.loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final u = filtered[i];
                        final String fallbackId = u.effectiveUid ?? u.uid;
                        final String display =
                            (u.displayName.trim().isEmpty)
                                ? fallbackId
                                : u.displayName;

                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(
                            display,
                            style: theme.textTheme.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap:
                              () => Navigator.of(
                                context,
                                rootNavigator: false,
                              ).pop(
                                _CreatePickedRecipient(
                                  id: fallbackId,
                                  name: display,
                                ),
                              ),
                        );
                      },
                    ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

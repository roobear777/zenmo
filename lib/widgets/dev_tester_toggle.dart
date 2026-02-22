import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DevTesterToggle extends StatefulWidget {
  const DevTesterToggle({super.key});

  @override
  State<DevTesterToggle> createState() => _DevTesterToggleState();
}

class _DevTesterToggleState extends State<DevTesterToggle> {
  bool _loading = true;
  bool _isTester = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Not signed in');
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      setState(() => _isTester = (snap.data()?['isTester'] == true));
    } catch (e) {
      setState(() => _error = 'Failed to load tester flag.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(bool v) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Not signed in');
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'isTester': v,
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() => _isTester = v);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(v ? 'Tester mode ON' : 'Tester mode OFF')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Failed to update tester flag.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        title: Text('Tester mode'),
        subtitle: Text('Loading…'),
        trailing: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Tester mode'),
          subtitle: Text(
            _isTester
                ? 'Unlimited fingerprint redos (limit bypassed)'
                : 'Monthly limit enforced',
          ),
          value: _isTester,
          onChanged: (v) => _set(v),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

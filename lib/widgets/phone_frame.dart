import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Wraps content in a phone-sized frame on web, full screen on mobile
class PhoneFrame extends StatelessWidget {
  final Widget child;

  const PhoneFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      // On mobile: just show the child full screen
      return child;
    }

    // On web: show in a phone-sized frame
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Container(
          width: 414, // iPhone XR width
          height: 896, // iPhone XR height
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

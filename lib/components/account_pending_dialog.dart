import 'package:flutter/material.dart';

/// Tells a newly registered (or not yet approved) user to wait for admin approval.
Future<void> showAccountPendingDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.hourglass_top_rounded, size: 32),
      title: const Text('Waiting for access approval'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

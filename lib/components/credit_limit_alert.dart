import 'package:flutter/material.dart';
import 'package:pwa/services/credit_service.dart';

Future<void> showCreditLimitAlert(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: const Text(CreditService.limitMessage),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    ),
  );
}

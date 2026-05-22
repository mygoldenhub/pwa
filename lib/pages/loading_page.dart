import 'package:flutter/material.dart';
import 'package:pwa/theme.dart';

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: cs.primary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Loading…',
                  style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

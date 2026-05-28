import 'package:flutter/material.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/theme.dart';

class InvoicePage extends StatelessWidget {
  const InvoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const AppImpactHeader(title: 'Invoice'),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: AppSpacing.paddingXl,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  color: cs.surface,
                  border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long, size: 48, color: cs.primary),
                    const SizedBox(height: AppSpacing.md),
                    Text('Invoices', style: Theme.of(context).textTheme.titleLarge?.semiBold),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'This tab will show your pending and completed invoices.\nWe can wire it up to Xero next.',
                      style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

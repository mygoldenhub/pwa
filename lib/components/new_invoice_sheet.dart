import 'package:flutter/material.dart';
import 'package:pwa/theme.dart';

enum LineAmountType { exclusive, inclusive, noTax }

extension LineAmountTypeUi on LineAmountType {
  String get label => switch (this) {
    LineAmountType.exclusive => 'Exclusive',
    LineAmountType.inclusive => 'Inclusive',
    LineAmountType.noTax => 'No Tax',
  };
}

class InvoiceDraft {
  final int totalBudgetCents;
  final String reference;
  final String currencyCode;
  final double currencyRate;
  final LineAmountType lineAmountType;
  final DateTime date;
  final DateTime dueDate;

  const InvoiceDraft({
    required this.totalBudgetCents,
    required this.reference,
    required this.currencyCode,
    required this.currencyRate,
    required this.lineAmountType,
    required this.date,
    required this.dueDate,
  });
}

/// Bottom-sheet modal used from the Cart page to collect invoice metadata.
///
/// Returns an [InvoiceDraft] via `Navigator.pop(context, draft)` when the user
  /// taps "Create".
class NewInvoiceSheet extends StatefulWidget {
  final int totalBudgetCents;

  const NewInvoiceSheet({super.key, required this.totalBudgetCents});

  @override
  State<NewInvoiceSheet> createState() => _NewInvoiceSheetState();
}

class _NewInvoiceSheetState extends State<NewInvoiceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _referenceCtrl = TextEditingController();

  // Per requirement: currency is AUD only.
  static const String _fixedCurrencyCode = 'AUD';
  static const double _fixedCurrencyRate = 1.0;

  // Per requirement: fixed values (not editable).
  static const LineAmountType _fixedLineAmountType = LineAmountType.exclusive;
  late final DateTime _date;

  DateTime get _dueDate => _date.add(const Duration(days: 7));

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _referenceCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    Navigator.of(context).pop(
      InvoiceDraft(
        totalBudgetCents: widget.totalBudgetCents,
        reference: _referenceCtrl.text.trim(),
        currencyCode: _fixedCurrencyCode,
        currencyRate: _fixedCurrencyRate,
        lineAmountType: _fixedLineAmountType,
        date: _date,
        dueDate: _dueDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = (widget.totalBudgetCents / 100).toStringAsFixed(2);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                    ),
                    child: Icon(Icons.note_add_outlined, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text('New Invoice', style: Theme.of(context).textTheme.titleLarge?.semiBold)),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Confirm invoice details before creating it.',
                style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              _ReadOnlyMetricField(label: 'Total budget', value: '\$$total'),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _referenceCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Reference',
                  prefixIcon: Icon(Icons.tag_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a reference.' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _ReadOnlyMetricField(label: 'Currency', value: _fixedCurrencyCode),
              const SizedBox(height: AppSpacing.md),
              _ReadOnlyInputField(label: 'Line amount type', value: _fixedLineAmountType.label, prefixIcon: Icons.rule_folder_outlined),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _ReadOnlyInputField(label: 'Date', value: _fmtDate(_date), prefixIcon: Icons.event),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _ReadOnlyInputField(label: 'Due date', value: _fmtDate(_dueDate), prefixIcon: Icons.event_available),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: Icon(Icons.receipt_long, color: cs.onPrimary),
                      label: Text('Create', style: TextStyle(color: cs.onPrimary)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back, color: cs.onSurface),
                      label: Text('Back', style: TextStyle(color: cs.onSurface)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyMetricField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyMetricField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant))),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.semiBold),
        ],
      ),
    );
  }
}

class _ReadOnlyInputField extends StatelessWidget {
  final String label;
  final String value;
  final IconData prefixIcon;

  const _ReadOnlyInputField({required this.label, required this.value, required this.prefixIcon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(prefixIcon),
      ),
      child: Text(value, style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurface)),
    );
  }
}

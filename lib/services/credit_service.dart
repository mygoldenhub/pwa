import 'package:pwa/supabase/supabase_config.dart';

class CreditAccount {
  final double plan;
  final double used;

  const CreditAccount({required this.plan, required this.used});
}

class CreditService {
  static const String limitMessage = 'Upgrade Credit Plan! You already used credit limit.';

  static Future<CreditAccount> loadMine() async {
    final id = SupabaseConfig.auth.currentUser?.id;
    if (id == null || id.isEmpty) throw 'Not signed in.';
    final row = await SupabaseConfig.client.from('users').select('credit_plan, credit_used').eq('id', id).maybeSingle();
    if (row == null) throw 'Could not load your credit plan.';
    return CreditAccount(
      plan: _num(row['credit_plan'], 1000),
      used: _num(row['credit_used'], 0),
    );
  }

  /// True when [plan] is at least credit already used plus this payment.
  static bool covers({required double plan, required double used, required int payCents}) {
    if (payCents <= 0) return true;
    final availableCents = ((plan - used) * 100).round();
    return availableCents >= payCents;
  }

  static int totalCents(List<({String name, int unitAmountCents, int quantity})> items) {
    var cents = 0;
    for (final item in items) {
      if (item.unitAmountCents <= 0 || item.quantity <= 0) continue;
      cents += item.unitAmountCents * item.quantity;
    }
    return cents;
  }

  /// Adds a successful payment to the signed-in user's credit_used.
  /// When used credit is then over 90% of the plan, the database sends that user a broadcast.
  static Future<void> recordPayment(double amount) async {
    if (amount <= 0) return;
    await SupabaseConfig.client.rpc('record_credit_use', params: {'pay_amount': amount});
  }

  static double _num(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

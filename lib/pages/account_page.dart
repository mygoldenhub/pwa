import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/auth_service.dart';
import 'package:pwa/theme.dart';

class AccountPage extends StatefulWidget {
  final AppState appState;
  const AccountPage({super.key, required this.appState});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _busy = false;

  Future<T?> _showCenteredModal<T>({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return LayoutBuilder(
          builder: (context, viewport) {
            final viewInsets = MediaQuery.viewInsetsOf(context);
            final safePadding = MediaQuery.paddingOf(context);

            // Keep generous padding on all devices, but also ensure we still
            // have enough space on very small screens / when keyboard is open.
            final outerPadding = EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg + safePadding.top,
              AppSpacing.lg,
              AppSpacing.lg + safePadding.bottom + viewInsets.bottom,
            );

            final rawMaxHeight = viewport.maxHeight - outerPadding.vertical;
            final maxHeight = rawMaxHeight < 0 ? 0.0 : rawMaxHeight;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: outerPadding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
                  child: Material(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    clipBehavior: Clip.antiAlias,
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        primary: false,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1).animate(curved), child: child),
        );
      },
    );
  }

  Future<void> _run(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
    } catch (e) {
      debugPrint('AccountPage action failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showUpdatePasswordFlow() async {
    final currentPassword = await _showCenteredModal<String>(child: _PasswordGateSheet(auth: widget.appState.auth));
    if (!mounted || currentPassword == null) return;

    final newPassword = await _showCenteredModal<String>(child: const _UpdatePasswordSheet());
    if (!mounted || newPassword == null) return;

    await _run(() async {
      await widget.appState.auth.updatePassword(currentPassword: currentPassword, newPassword: newPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated.')));
    });
  }

  Future<void> _showUpdatePinFlow() async {
    final currentPassword = await _showCenteredModal<String>(child: _PasswordGateSheet(auth: widget.appState.auth));
    if (!mounted || currentPassword == null) return;

    final newPin = await _showCenteredModal<String>(child: const _UpdatePinSheet());
    if (!mounted || newPin == null) return;

    await _run(() async {
      await widget.appState.auth.updatePin(currentPassword: currentPassword, newPin: newPin);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN updated.')));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = widget.appState.auth.currentUser;

    return Scaffold(
      appBar: const AppImpactHeader(title: 'Account'),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator.adaptive(
              onRefresh: () async => widget.appState.auth.refreshProfile(),
              child: ListView(
                padding: AppSpacing.paddingLg,
                children: [
                  _ProfileCard(
                    displayName: user?.displayName ?? '—',
                    email: user?.email ?? '—',
                    companyName: (user?.companyName?.trim().isNotEmpty ?? false) ? user!.companyName!.trim() : '—',
                    phoneNumber: (user?.phoneNumber?.trim().isNotEmpty ?? false) ? user!.phoneNumber!.trim() : '—',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SectionTitle(title: 'Security'),
                  const SizedBox(height: AppSpacing.sm),
                  _ActionCard(
                    title: 'Update password',
                    subtitle: 'Change the password used for sign-in',
                    icon: Icons.lock_outline,
                    onTap: _busy ? null : _showUpdatePasswordFlow,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ActionCard(
                    title: 'Update PIN',
                    subtitle: '4-digit PIN for quick access',
                    icon: Icons.pin_outlined,
                    onTap: _busy ? null : _showUpdatePinFlow,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionTitle(title: 'Session'),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              await _run(() async {
                                await widget.appState.auth.signOut();
                                if (context.mounted) context.go(AppRoutes.login);
                              });
                            },
                      style: FilledButton.styleFrom(backgroundColor: cs.error),
                      icon: Icon(Icons.logout, color: cs.onError),
                      label: Text('Logout', style: TextStyle(color: cs.onError)),
                    ),
                  ),
                ],
              ),
            ),
            if (_busy || widget.appState.auth.isLoading)
              Positioned.fill(
                child: AbsorbPointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.55)),
                    child: Center(child: CircularProgressIndicator(color: cs.primary)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String displayName;
  final String email;
  final String companyName;
  final String phoneNumber;

  const _ProfileCard({
    required this.displayName,
    required this.email,
    required this.companyName,
    required this.phoneNumber,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: cs.surface,
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  color: cs.surfaceContainerHighest,
                  border: Border.all(color: cs.outline.withValues(alpha: 0.14)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.person, color: cs.primary),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: Theme.of(context).textTheme.titleLarge?.semiBold),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Company name',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  companyName.isEmpty ? '—' : companyName,
                  style: const TextStyle(
                    fontSize: 17,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phone Number',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phoneNumber.isEmpty ? '—' : phoneNumber,
                  style: const TextStyle(
                    fontSize: 17,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall?.withColor(cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text(value, style: Theme.of(context).textTheme.bodyMedium?.semiBold),
              ],
            ),
          ),
          Icon(Icons.lock_outline, size: 18, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: onTap == null ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            color: cs.surface,
            border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  color: cs.primaryContainer,
                ),
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.semiBold),
                    const SizedBox(height: AppSpacing.xs),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomSheetScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _BottomSheetScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, bottom: AppSpacing.lg + bottomPadding, top: AppSpacing.md),
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
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  color: cs.surfaceContainerHighest,
                  border: Border.all(color: cs.outline.withValues(alpha: 0.14)),
                ),
                child: Icon(icon, color: cs.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge?.semiBold),
                    const SizedBox(height: AppSpacing.xs),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _PasswordGateSheet extends StatefulWidget {
  final AuthService auth;
  const _PasswordGateSheet({required this.auth});

  @override
  State<_PasswordGateSheet> createState() => _PasswordGateSheetState();
}

class _PasswordGateSheetState extends State<_PasswordGateSheet> {
  final _controller = TextEditingController();
  bool _show = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BottomSheetScaffold(
      title: 'Confirm password',
      subtitle: 'For security, please enter your current password.',
      icon: Icons.verified_user_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            obscureText: !_show,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Current password',
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide' : 'Show',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _busy ? null : () => _submit(context),
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.auth.verifyCurrentPassword(password: value);
      if (!context.mounted) return;
      context.pop(value);
    } catch (e) {
      debugPrint('PasswordGateSheet verify failed: $e');
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _UpdatePasswordSheet extends StatefulWidget {
  const _UpdatePasswordSheet();

  @override
  State<_UpdatePasswordSheet> createState() => _UpdatePasswordSheetState();
}

class _UpdatePasswordSheetState extends State<_UpdatePasswordSheet> {
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _BottomSheetScaffold(
      title: 'New password',
      subtitle: 'Use at least 8 chars with upper, lower, and a number.',
      icon: Icons.lock_reset_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _newController,
            obscureText: !_show,
            decoration: InputDecoration(
              labelText: 'New password',
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide' : 'Show',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _confirmController,
            obscureText: !_show,
            decoration: const InputDecoration(labelText: 'Confirm new password'),
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'This will also update PIN-login on this device.',
                  style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: () => _submit(context),
            child: const Text('Update password'),
          ),
        ],
      ),
    );
  }

  void _submit(BuildContext context) {
    final p1 = _newController.text.trim();
    final p2 = _confirmController.text.trim();
    if (p1.isEmpty) {
      setState(() => _error = 'Please enter a new password.');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    context.pop(p1);
  }
}

class _UpdatePinSheet extends StatefulWidget {
  const _UpdatePinSheet();

  @override
  State<_UpdatePinSheet> createState() => _UpdatePinSheetState();
}

class _UpdatePinSheetState extends State<_UpdatePinSheet> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _BottomSheetScaffold(
      title: 'New PIN',
      subtitle: 'Choose a 4-digit PIN.',
      icon: Icons.pin_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'New PIN (4 digits)', errorText: _error),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _confirmController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Confirm PIN'),
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Your PIN is stored securely as a hash in Supabase.',
                  style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: () => _submit(context),
            child: const Text('Update PIN'),
          ),
        ],
      ),
    );
  }

  void _submit(BuildContext context) {
    final pin1 = _pinController.text.trim();
    final pin2 = _confirmController.text.trim();
    if (pin1.length != 4 || pin1.contains(RegExp(r'\D'))) {
      setState(() => _error = 'PIN must be exactly 4 digits.');
      return;
    }
    if (pin1 != pin2) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    context.pop(pin1);
  }
}

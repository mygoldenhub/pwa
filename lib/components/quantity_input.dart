import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pwa/theme.dart';

/// Quantity selector that supports both +/- stepping and direct numeric input.
///
/// - `value` is the current quantity.
/// - `onChanged` fires for *immediate* local updates (e.g., product detail page).
/// - `onCommitted` fires when the user finishes editing (submit / focus loss),
///   or when +/- buttons are used. Use this for server writes (e.g., cart).
class QuantityInput extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final bool isLoading;
  /// Use a smaller, more compact layout (better for tight list rows).
  final bool compact;
  /// When `true`, typing will trigger a debounced `onCommitted`.
  ///
  /// Set this to `false` for scenarios like Cart where you only want to write
  /// to the backend when the user finishes editing (focus loss / submit).
  final bool commitWhileTyping;
  final ValueChanged<int>? onChanged;
  final ValueChanged<int>? onCommitted;

  const QuantityInput({
    super.key,
    required this.value,
    this.min = 1,
    this.max = 9999,
    this.enabled = true,
    this.isLoading = false,
    this.compact = false,
    this.commitWhileTyping = true,
    this.onChanged,
    this.onCommitted,
  });

  @override
  State<QuantityInput> createState() => _QuantityInputState();
}

class _QuantityInputState extends State<QuantityInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _commitDebounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant QuantityInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _commitDebounce?.cancel();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commitFromText();
  }

  int _clamp(int v) => v.clamp(widget.min, widget.max);

  int? _parseAndSanitizeFromText() {
    final raw = _controller.text.trim();
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      _controller.text = widget.value.toString();
      return null;
    }
    final next = _clamp(parsed);
    if (next.toString() != _controller.text) {
      _controller.text = next.toString();
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }
    return next;
  }

  void _previewFromText() {
    final next = _parseAndSanitizeFromText();
    if (next == null || next == widget.value) return;
    widget.onChanged?.call(next);
  }

  void _commitFromText() {
    final next = _parseAndSanitizeFromText();
    if (next == null || next == widget.value) return;
    widget.onChanged?.call(next);
    widget.onCommitted?.call(next);
  }

  void _debouncedCommitFromText() {
    final next = _parseAndSanitizeFromText();
    if (next == null || next == widget.value) return;
    widget.onChanged?.call(next);
    if (widget.onCommitted == null) return;

    _commitDebounce?.cancel();
    _commitDebounce = Timer(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      if (next != widget.value) widget.onCommitted!.call(next);
    });
  }

  void _stepBy(int delta) {
    if (!widget.enabled || widget.isLoading) return;
    final next = _clamp(widget.value + delta);
    if (next == widget.value) return;
    _controller.text = next.toString();
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    widget.onChanged?.call(next);
    widget.onCommitted?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final canDec = widget.value > widget.min;
    final canInc = widget.value < widget.max;

    final outerPadding = widget.compact ? const EdgeInsets.all(4) : const EdgeInsets.all(6);
    final fieldWidth = widget.compact ? 56.0 : 72.0;
    final fieldHeight = widget.compact ? 40.0 : 44.0;
    final buttonExtent = widget.compact ? 38.0 : 44.0;
    final iconSize = widget.compact ? 18.0 : 20.0;
    final gap = widget.compact ? AppSpacing.xs : AppSpacing.sm;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: widget.enabled ? 1.0 : 0.55,
      child: Container(
        padding: outerPadding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _QtyIconButton(
              tooltip: 'Decrease',
              icon: Icons.remove,
              enabled: widget.enabled && !widget.isLoading && canDec,
              onTap: () => _stepBy(-1),
              extent: buttonExtent,
              iconSize: iconSize,
            ),
            SizedBox(width: gap),
            SizedBox(
              width: fieldWidth,
              height: fieldHeight,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled && !widget.isLoading,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                style: (widget.compact ? tt.titleSmall : tt.titleMedium)?.copyWith(fontWeight: FontWeight.w900),
                maxLength: 4,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 10, vertical: widget.compact ? 10 : 12),
                  filled: true,
                  fillColor: cs.surface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.55), width: 1.4),
                  ),
                ),
                onChanged: (_) {
                  if (!widget.commitWhileTyping) {
                    _previewFromText();
                  } else {
                    _debouncedCommitFromText();
                  }
                },
                onSubmitted: (_) => _commitFromText(),
              ),
            ),
            SizedBox(width: gap),
            _QtyIconButton(
              tooltip: 'Increase',
              icon: Icons.add,
              enabled: widget.enabled && !widget.isLoading && canInc,
              onTap: () => _stepBy(1),
              extent: buttonExtent,
              iconSize: iconSize,
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final double extent;
  final double iconSize;

  const _QtyIconButton({required this.tooltip, required this.icon, required this.enabled, required this.onTap, required this.extent, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        constraints: BoxConstraints.tightFor(width: extent, height: extent),
        padding: EdgeInsets.zero,
        onPressed: enabled ? onTap : null,
        style: IconButton.styleFrom(
          backgroundColor: enabled ? cs.primaryContainer : cs.surface,
          foregroundColor: enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant.withValues(alpha: 0.55),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
        icon: Icon(icon, size: iconSize),
      ),
    );
  }
}

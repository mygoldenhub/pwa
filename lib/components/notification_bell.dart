import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/notification_service.dart';
import 'package:pwa/utils/app_time.dart';

/// Header bell: active (with unread count) when the user has unread broadcast announcements.
/// Tap shows the latest notifications; "Show more" opens the Notifications page.
class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key});

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  static const int _previewCount = 5;

  final MenuController _menu = MenuController();
  late final Stream<List<AppNotification>> _stream = NotificationService.streamMyNotifications();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: _stream,
      builder: (context, snap) {
        final items = snap.data ?? const <AppNotification>[];
        final unread = items.where((n) => !n.isRead).length;
        return MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(0, 8),
          style: MenuStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
          menuChildren: [
            _NotificationPanel(
              items: items.take(_previewCount).toList(),
              total: items.length,
              unread: unread,
              loading: snap.connectionState == ConnectionState.waiting && !snap.hasData,
              onOpen: (n) {
                _menu.close();
                showNotificationDetail(context, n);
              },
              onMarkAllRead: () => NotificationService.markAllRead(items.where((n) => !n.isRead).map((n) => n.id)),
              onShowMore: () {
                _menu.close();
                context.push(AppRoutes.notifications);
              },
            ),
          ],
          builder: (context, controller, _) => _BellIcon(
            unread: unread,
            onTap: () => controller.isOpen ? controller.close() : controller.open(),
          ),
        );
      },
    );
  }
}

class _BellIcon extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;

  const _BellIcon({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = unread > 0;
    return Semantics(
      button: true,
      label: active ? 'Notifications, $unread unread' : 'Notifications',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: active ? cs.primary : cs.surface,
                shape: BoxShape.circle,
                border: Border.all(color: cs.primary.withValues(alpha: active ? 0.22 : 0.45)),
              ),
              child: Icon(
                active ? Icons.notifications_active : Icons.notifications_none,
                size: 20,
                color: active ? cs.onPrimary : cs.primary,
              ),
            ),
            if (active)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.surface, width: 1.5),
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: TextStyle(color: cs.onError, fontSize: 10, fontWeight: FontWeight.w800, height: 1.1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  final List<AppNotification> items;
  final int total;
  final int unread;
  final bool loading;
  final ValueChanged<AppNotification> onOpen;
  final VoidCallback onMarkAllRead;
  final VoidCallback onShowMore;

  const _NotificationPanel({
    required this.items,
    required this.total,
    required this.unread,
    required this.loading,
    required this.onOpen,
    required this.onMarkAllRead,
    required this.onShowMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: width < 380 ? width - 24 : 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Notifications', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (unread > 0) TextButton(onPressed: onMarkAllRead, child: const Text('Mark all as read')),
              ],
            ),
          ),
          const Divider(height: 1),
          if (loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No notifications yet', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            )
          else
            ConstrainedBox(
              // Leave room for the header bar, panel title and "Show more" on short windows.
              constraints: BoxConstraints(
                maxHeight: math.max(120.0, math.min(MediaQuery.sizeOf(context).height * 0.6, MediaQuery.sizeOf(context).height - 260)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final n in items) NotificationTile(notification: n, onTap: () => onOpen(n), maxBodyLines: 2),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          TextButton(
            onPressed: onShowMore,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(total > items.length ? 'Show more ($total)' : 'Show more'),
          ),
        ],
      ),
    );
  }
}

/// One notification row, shared by the bell panel and the Notifications page.
class NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final int? maxBodyLines;

  const NotificationTile({super.key, required this.notification, required this.onTap, this.maxBodyLines});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final n = notification;
    return Material(
      color: n.isRead ? Colors.transparent : cs.primary.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 10),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: n.isRead ? Colors.transparent : cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      maxLines: maxBodyLines,
                      overflow: maxBodyLines == null ? null : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(AppTime.formatDateTime(n.createdAt), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the full announcement and marks it read.
Future<void> showNotificationDetail(BuildContext context, AppNotification n) {
  if (!n.isRead) unawaited(NotificationService.markRead(n.id));
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final size = MediaQuery.sizeOf(context);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
                color: cs.primary.withValues(alpha: 0.06),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.campaign_rounded, color: cs.onPrimary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            n.title.isEmpty ? 'Announcement' : n.title,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.schedule_rounded, size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  AppTime.formatDateTime(n.createdAt),
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
              // Body (scrolls when long)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: SelectableText(n.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

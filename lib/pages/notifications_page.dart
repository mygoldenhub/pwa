import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/components/notification_bell.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/notification_service.dart';
import 'package:pwa/theme.dart';
import 'package:pwa/utils/app_time.dart';

/// All broadcast announcements for the signed-in user, with per-user read state.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

enum _Filter { all, unread }

class _NotificationsPageState extends State<NotificationsPage> {
  static const int _pageSize = 10;

  late final Stream<List<AppNotification>> _stream = NotificationService.streamMyNotifications();
  int _page = 0;
  _Filter _filter = _Filter.all;
  final Set<String> _dismissed = {};

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.cart);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Color.alphaBlend(cs.primary.withValues(alpha: 0.025), cs.surface),
      appBar: AppImpactHeader(
        title: 'Notifications',
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<AppNotification>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError && !snap.hasData) {
              return const _StateMessage(
                icon: Icons.cloud_off_rounded,
                title: 'Couldn\'t load notifications',
                subtitle: 'Please check your connection and try again.',
              );
            }
            final all = [
              for (final n in snap.data ?? const <AppNotification>[])
                if (!_dismissed.contains(n.id)) n,
            ];
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _content(context, all),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteNotification(AppNotification n) async {
    final title = n.title.trim().isEmpty ? 'this notification' : '"${n.title.trim()}"';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete notification?'),
        content: Text('$title will be removed from your notifications.'),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _dismissed.add(n.id));
    try {
      await NotificationService.dismiss(n.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _dismissed.remove(n.id));
      final missing = e.toString().toLowerCase().contains('announcement_dismissals');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missing
                ? 'Couldn\'t delete this notification. Run supabase/migrations/0016_announcement_dismissals.sql in the Supabase SQL editor.'
                : 'Couldn\'t delete this notification.',
          ),
        ),
      );
    }
  }

  Widget _content(BuildContext context, List<AppNotification> all) {
    final unreadIds = [for (final n in all) if (!n.isRead) n.id];
    final items = _filter == _Filter.unread ? [for (final n in all) if (!n.isRead) n] : all;

    final pageCount = items.isEmpty ? 1 : (items.length + _pageSize - 1) ~/ _pageSize;
    // Clamp in case the list shrank (e.g. an admin deleted announcements or items were read).
    final page = _page.clamp(0, pageCount - 1);
    final pageItems = items.skip(page * _pageSize).take(_pageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          total: all.length,
          unread: unreadIds.length,
          filter: _filter,
          onFilter: (f) => setState(() {
            _filter = f;
            _page = 0;
          }),
          onMarkAllRead: unreadIds.isEmpty ? null : () => NotificationService.markAllRead(unreadIds),
        ),
        Expanded(
          child: items.isEmpty
              ? (_filter == _Filter.unread && all.isNotEmpty
                  ? const _StateMessage(
                      icon: Icons.done_all_rounded,
                      title: 'You\'re all caught up',
                      subtitle: 'No unread notifications.',
                    )
                  : const _StateMessage(
                      icon: Icons.notifications_none_rounded,
                      title: 'No notifications yet',
                      subtitle: 'Announcements from Tile & Stone Trade Supply will show up here.',
                    ))
              : ListView.separated(
                  key: ValueKey('notifications-${_filter.name}-$page'),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                  itemCount: pageItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final n = pageItems[i];
                    return _NotificationCard(
                      notification: n,
                      onTap: () => showNotificationDetail(context, n),
                      onDelete: () => _deleteNotification(n),
                    );
                  },
                ),
        ),
        if (pageCount > 1)
          _Pager(
            page: page,
            pageCount: pageCount,
            start: page * _pageSize + 1,
            end: page * _pageSize + pageItems.length,
            total: items.length,
            onPage: (p) => setState(() => _page = p.clamp(0, pageCount - 1)),
          ),
      ],
    );
  }
}

/// "All / Unread" segmented filter, unread count and "Mark all as read".
class _Toolbar extends StatelessWidget {
  final int total;
  final int unread;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final VoidCallback? onMarkAllRead;

  const _Toolbar({
    required this.total,
    required this.unread,
    required this.filter,
    required this.onFilter,
    required this.onMarkAllRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<_Filter>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: _Filter.all, label: Text('All ($total)')),
              ButtonSegment(value: _Filter.unread, label: Text('Unread ($unread)')),
            ],
            selected: {filter},
            onSelectionChanged: (s) => onFilter(s.first),
          ),
          TextButton.icon(
            onPressed: onMarkAllRead,
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('Mark all as read'),
            style: TextButton.styleFrom(foregroundColor: cs.primary),
          ),
        ],
      ),
    );
  }
}

/// Fixed-height card: 1-line title, 2-line preview (ellipsized). Tap opens the full notification.
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationCard({required this.notification, required this.onTap, required this.onDelete});

  static const double height = 104;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final n = notification;
    final unread = !n.isRead;
    final radius = BorderRadius.circular(AppRadius.lg);

    return Material(
      color: unread ? Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: unread ? cs.primary.withValues(alpha: 0.28) : cs.outline.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Row(
                  children: [
                    // Accent bar for unread items.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 4,
                      color: unread ? cs.primary : Colors.transparent,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _Avatar(unread: unread),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.title.isEmpty ? 'Announcement' : n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Text(
                                n.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 2, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      _relativeTime(n.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: unread ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final bool unread;
  const _Avatar({required this.unread});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: unread ? cs.primary : cs.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            unread ? Icons.notifications_rounded : Icons.notifications_none_rounded,
            size: 22,
            color: unread ? cs.onPrimary : cs.primary.withValues(alpha: 0.7),
          ),
        ),
        if (unread)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: cs.error,
                shape: BoxShape.circle,
                border: Border.all(color: cs.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pager extends StatelessWidget {
  final int page;
  final int pageCount;
  final int start;
  final int end;
  final int total;
  final ValueChanged<int> onPage;

  const _Pager({
    required this.page,
    required this.pageCount,
    required this.start,
    required this.end,
    required this.total,
    required this.onPage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Previous page',
              onPressed: page > 0 ? () => onPage(page - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Page ${page + 1} of $pageCount', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text('$start–$end of $total', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Next page',
              onPressed: page < pageCount - 1 ? () => onPage(page + 1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _StateMessage({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// "Just now", "5m ago", "3h ago", "Yesterday", "4d ago", then the local date.
String _relativeTime(DateTime? createdAt) {
  if (createdAt == null) return '';
  final diff = DateTime.now().toUtc().difference(createdAt.toUtc());
  if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return AppTime.formatDateDmy(createdAt);
}

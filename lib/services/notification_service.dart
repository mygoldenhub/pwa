import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pwa/supabase/supabase_config.dart';
import 'package:pwa/utils/app_time.dart';

/// A broadcast announcement as seen by the signed-in user.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool isRead;

  /// Empty when the broadcast was posted to everyone.
  final List<String> recipientNames;
  final bool sendsToEveryone;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.recipientNames = const [],
    this.sendsToEveryone = true,
  });

  /// "To: Everyone", or "To:" plus up to three first names, with "..." when there are more.
  String get audienceBadge {
    if (sendsToEveryone) return 'To: Everyone';
    final names = [
      for (final name in recipientNames)
        if (name.trim().isNotEmpty) name.trim(),
    ];
    if (names.isEmpty) return 'To: Specific people';
    if (names.length <= 3) return 'To: ${names.join(', ')}';
    return 'To: ${names.take(3).join(', ')}...';
  }
}

/// Broadcast announcements with per-user read state (`announcement_reads`).
class NotificationService {
  static const String _announcements = 'announcements';
  static const String _reads = 'announcement_reads';
  static const String _dismissals = 'announcement_dismissals';

  static String? get _userId {
    final id = SupabaseConfig.auth.currentUser?.id;
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Live list of all announcements (newest first) with this user's read flags.
  static Stream<List<AppNotification>> streamMyNotifications() {
    final userId = _userId;
    if (userId == null) return Stream.value(const <AppNotification>[]);

    final controller = StreamController<List<AppNotification>>();
    List<Map<String, dynamic>>? announcements;
    Set<String> readIds = <String>{};
    Set<String> dismissedIds = <String>{};
    var readsReady = false;
    var dismissalsReady = false;
    StreamSubscription? annSub;
    StreamSubscription? readSub;
    StreamSubscription? dismissSub;

    void emit() {
      final rows = announcements;
      // Wait for read and dismissal snapshots. Until then every row looks unread,
      // and the bell would flash the full broadcast count.
      if (rows == null || !readsReady || !dismissalsReady || controller.isClosed) return;
      final list = rows.where((row) {
        final id = (row['id'] ?? '').toString();
        return _visibleTo(row, userId) && !dismissedIds.contains(id);
      }).map((row) {
        final id = (row['id'] ?? '').toString();
        return AppNotification(
          id: id,
          title: (row['title'] ?? '').toString(),
          body: (row['body'] ?? '').toString(),
          createdAt: AppTime.parseUtc(row['created_at']),
          isRead: readIds.contains(id),
          sendsToEveryone: _sendsToEveryone(row),
          recipientNames: _nameList(row['recipient_names']),
        );
      }).toList()
        ..sort((a, b) {
          final ad = a.createdAt, bd = b.createdAt;
          if (ad == null || bd == null) return 0;
          return bd.compareTo(ad);
        });
      controller.add(list);
    }

    controller.onListen = () {
      annSub = SupabaseConfig.client
          .from(_announcements)
          .stream(primaryKey: const ['id'])
          .order('created_at', ascending: false)
          .listen((rows) {
        announcements = rows;
        emit();
      }, onError: (Object e) {
        debugPrint('NotificationService announcements stream error: $e');
        if (!controller.isClosed) controller.addError(e);
      });

      readSub = SupabaseConfig.client
          .from(_reads)
          .stream(primaryKey: const ['user_id', 'announcement_id'])
          .eq('user_id', userId)
          .listen((rows) {
        readIds = {for (final r in rows) (r['announcement_id'] ?? '').toString()};
        readsReady = true;
        emit();
      }, onError: (Object e) {
        // Read state is non-critical: keep showing announcements (all unread).
        debugPrint('NotificationService reads stream error: $e');
        readsReady = true;
        emit();
      });

      dismissSub = SupabaseConfig.client
          .from(_dismissals)
          .stream(primaryKey: const ['user_id', 'announcement_id'])
          .eq('user_id', userId)
          .listen((rows) {
        dismissedIds = {for (final r in rows) (r['announcement_id'] ?? '').toString()};
        dismissalsReady = true;
        emit();
      }, onError: (Object e) {
        // Dismissals are non-critical: keep showing announcements until the table exists.
        debugPrint('NotificationService dismissals stream error: $e');
        dismissalsReady = true;
        emit();
      });
    };

    controller.onCancel = () async {
      await annSub?.cancel();
      await readSub?.cancel();
      await dismissSub?.cancel();
      await controller.close();
    };

    return controller.stream;
  }

  /// Null or an empty recipient list means the broadcast is for everyone.
  static bool _sendsToEveryone(Map<String, dynamic> row) {
    final raw = row['recipient_ids'];
    if (raw == null) return true;
    if (raw is List) return raw.isEmpty;
    if (raw is String) {
      final trimmed = raw.trim();
      return trimmed.isEmpty || trimmed == '{}';
    }
    return true;
  }

  static bool _visibleTo(Map<String, dynamic> row, String userId) {
    if (_sendsToEveryone(row)) return true;
    final raw = row['recipient_ids'];
    if (raw is List) return raw.any((id) => id.toString() == userId);
    return raw.toString().contains(userId);
  }

  static List<String> _nameList(dynamic value) {
    if (value is List) {
      return [
        for (final name in value)
          if (name != null && name.toString().trim().isNotEmpty) name.toString().trim(),
      ];
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed == '{}') return const [];
      final inner = trimmed.startsWith('{') && trimmed.endsWith('}')
          ? trimmed.substring(1, trimmed.length - 1)
          : trimmed;
      return [
        for (final part in inner.split(','))
          if (part.trim().isNotEmpty) part.trim().replaceAll('"', ''),
      ];
    }
    return const [];
  }

  /// Removes one broadcast from this user's notification list. Other users still see it.
  static Future<void> dismiss(String announcementId) async {
    final userId = _userId;
    if (userId == null || announcementId.isEmpty) return;
    await SupabaseConfig.client.from(_dismissals).upsert(
      {'user_id': userId, 'announcement_id': announcementId},
      onConflict: 'user_id,announcement_id',
      ignoreDuplicates: true,
    );
  }

  static Future<void> markRead(String announcementId) => markAllRead([announcementId]);

  static Future<void> markAllRead(Iterable<String> announcementIds) async {
    final userId = _userId;
    final ids = announcementIds.where((id) => id.isNotEmpty).toSet();
    if (userId == null || ids.isEmpty) return;
    try {
      await SupabaseConfig.client.from(_reads).upsert(
        [for (final id in ids) {'user_id': userId, 'announcement_id': id}],
        onConflict: 'user_id,announcement_id',
        ignoreDuplicates: true,
      );
    } catch (e) {
      debugPrint('NotificationService.markAllRead failed: $e');
    }
  }
}

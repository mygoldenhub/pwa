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

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
  });
}

/// Broadcast announcements with per-user read state (`announcement_reads`).
class NotificationService {
  static const String _announcements = 'announcements';
  static const String _reads = 'announcement_reads';

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
    StreamSubscription? annSub;
    StreamSubscription? readSub;

    void emit() {
      final rows = announcements;
      if (rows == null || controller.isClosed) return;
      final list = rows.map((row) {
        final id = (row['id'] ?? '').toString();
        return AppNotification(
          id: id,
          title: (row['title'] ?? '').toString(),
          body: (row['body'] ?? '').toString(),
          createdAt: AppTime.parseUtc(row['created_at']),
          isRead: readIds.contains(id),
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
        emit();
      }, onError: (Object e) {
        // Read state is non-critical: keep showing announcements (all unread).
        debugPrint('NotificationService reads stream error: $e');
      });
    };

    controller.onCancel = () async {
      await annSub?.cancel();
      await readSub?.cancel();
      await controller.close();
    };

    return controller.stream;
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

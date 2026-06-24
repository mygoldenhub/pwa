import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Generic Supabase configuration template
/// Replace YOUR_ and YOUR_ with your actual values
class SupabaseConfig {
  static const String supabaseUrl = 'https://psvlvrdgwtnpwwhkbqfl.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzdmx2cmRnd3RucHd3aGticWZsIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjI0MTU0MiwiZXhwIjoyMDk3ODE3NTQyfQ.SeGhetc5WuOYi-SCSbWc4V_gtqMy0hDFXojNsr1LTRo';

  /// Returns the absolute HTTPS URL for an Edge Function.
  /// Example: https://<project>.supabase.co/functions/v1/check_email_exists
  ///
  /// This is mainly for logging / debugging; for calls, prefer
  /// `SupabaseConfig.client.functions.invoke()`.
  static Uri edgeFunctionUrl(String functionName) {
    final base = supabaseUrl.trim();
    final fn = functionName.trim();
    return Uri.parse('$base/functions/v1/$fn');
  }

  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: anonKey,
        debug: kDebugMode,
      );
      debugPrint('***** Supabase init completed *****');
    } catch (e) {
      debugPrint('Supabase.initialize failed: $e');
      rethrow;
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
}

/// Generic database service for CRUD operations
class SupabaseService {
  static const Duration _defaultTimeout = Duration(seconds: 20);

  /// Select multiple records from a table
  static Future<List<Map<String, dynamic>>> select(
    String table, {
    String? select,
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).select(select ?? '*');

      // Apply filters
      if (filters != null) {
        for (final entry in filters.entries) {
          query = query.eq(entry.key, entry.value);
        }
      }

      // Apply ordering
      if (orderBy != null) {
        query = query.order(orderBy, ascending: ascending);
      }

      // Apply limit
      if (limit != null) {
        query = query.limit(limit);
      }

      final res = await (query as Future).timeout(timeout);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw _handleDatabaseError('select', table, e);
    }
  }

  /// Select a single record from a table
  static Future<Map<String, dynamic>?> selectSingle(
    String table, {
    String? select,
    required Map<String, dynamic> filters,
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).select(select ?? '*');

      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }

      final res = await (query.maybeSingle() as Future).timeout(timeout);
      return res as Map<String, dynamic>?;
    } catch (e) {
      throw _handleDatabaseError('selectSingle', table, e);
    }
  }

  /// Insert a record into a table
  static Future<List<Map<String, dynamic>>> insert(
    String table,
    Map<String, dynamic> data,
    {Duration timeout = _defaultTimeout}
  ) async {
    try {
      final res = await SupabaseConfig.client.from(table).insert(data).select().timeout(timeout);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw _handleDatabaseError('insert', table, e);
    }
  }

  /// Insert multiple records into a table
  static Future<List<Map<String, dynamic>>> insertMultiple(
    String table,
    List<Map<String, dynamic>> data,
    {Duration timeout = _defaultTimeout}
  ) async {
    try {
      final res = await SupabaseConfig.client.from(table).insert(data).select().timeout(timeout);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw _handleDatabaseError('insertMultiple', table, e);
    }
  }

  /// Update records in a table
  static Future<List<Map<String, dynamic>>> update(
    String table,
    Map<String, dynamic> data, {
    required Map<String, dynamic> filters,
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).update(data);

      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }

      final res = await (query.select() as Future).timeout(timeout);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw _handleDatabaseError('update', table, e);
    }
  }

  /// Delete records from a table
  static Future<void> delete(
    String table, {
    required Map<String, dynamic> filters,
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).delete();

      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }

      await (query as Future).timeout(timeout);
    } catch (e) {
      throw _handleDatabaseError('delete', table, e);
    }
  }

  /// Get direct table reference for complex queries
  static SupabaseQueryBuilder from(String table) =>
      SupabaseConfig.client.from(table);

  /// Handle database errors
  static String _handleDatabaseError(
    String operation,
    String table,
    dynamic error,
  ) {
    if (error is TimeoutException) {
      return 'Request timed out while performing $operation on $table. Please check your connection and try again.';
    }
    if (error is PostgrestException) {
      return 'Failed to $operation from $table: ${error.message}';
    } else {
      return 'Failed to $operation from $table: ${error.toString()}';
    }
  }
}

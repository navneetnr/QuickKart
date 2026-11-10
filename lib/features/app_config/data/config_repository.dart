import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/app_config.dart';

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
    remoteUpdates: () => ref.read(mockServerProvider).configUpdates,
  ),
);

/// Loads remote config (think: Firebase Remote Config).
class ConfigRepository {
  ConfigRepository(
    this._client,
    this._store, {
    required Stream<int> Function() remoteUpdates,
  }) : _remoteUpdates = remoteUpdates;

  final ApiClient _client;
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config.
  Future<AppConfig> load() async {
    try {
      // Config notifications must fetch the newly published values, not a
      // still-fresh response from ApiClient's ordinary GET cache.
      final json = await _client.get('/v1/config', bypassCache: true)
          as Map<String, dynamic>;
      final values = (json['values'] as Map).cast<String, Object?>();
      final config = AppConfig.fromValues(values);
      try {
        await _store.setString(_cacheKey, jsonEncode(values));
      } catch (_) {
        // A cache write failure must not discard a successful network result.
      }
      return config;
    } catch (_) {
      try {
        final cached = await _store.getString(_cacheKey);
        if (cached != null) {
          final values = jsonDecode(cached);
          if (values is Map) {
            return AppConfig.fromValues(values.cast<String, Object?>());
          }
        }
      } catch (_) {
        // Corrupt or inaccessible cache falls through to safe defaults.
      }
      return AppConfig.defaults();
    }
  }

  static const _cacheKey = 'app_config.last_known_good.v1';
}

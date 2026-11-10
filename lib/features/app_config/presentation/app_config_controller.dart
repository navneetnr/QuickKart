import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/config_repository.dart';
import '../domain/app_config.dart';

/// The config the app is currently using. Hydrated in `main.dart` before the
/// first frame.
final appConfigControllerProvider =
    NotifierProvider<AppConfigController, AppConfig>(AppConfigController.new);

class AppConfigController extends Notifier<AppConfig> {
  StreamSubscription<int>? _subscription;

  @override
  AppConfig build() {
    final repository = ref.read(configRepositoryProvider);
    _subscription = repository.remoteUpdates.listen((_) {
      refresh();
    }, onError: (_) {});
    ref.onDispose(() => _subscription?.cancel());
    return AppConfig.defaults();
  }

  /// Used at startup with the config loaded during bootstrap.
  void hydrate(AppConfig config) => state = config;

  Future<void> refresh() async {
    state = await ref.read(configRepositoryProvider).load();
  }
}

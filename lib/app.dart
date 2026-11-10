import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/providers.dart';
import 'features/app_config/domain/update_policy.dart';
import 'features/app_config/presentation/app_config_controller.dart';
import 'features/catalog/presentation/home_screen.dart';

class QuickKartApp extends ConsumerWidget {
  const QuickKartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'QuickKart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0C831F),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      ),
      home: const _UpdateGate(),
    );
  }
}

class _UpdateGate extends ConsumerStatefulWidget {
  const _UpdateGate();

  @override
  ConsumerState<_UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<_UpdateGate> {
  static const _dismissedVersionKey = 'update.optional_dismissed_version';
  bool _promptOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOptionalIfNeeded());
  }

  Future<void> _showOptionalIfNeeded() async {
    if (!mounted || _promptOpen) return;
    final config = ref.read(appConfigControllerProvider);
    final requirement = UpdatePolicy.evaluate(
      currentVersion: ref.read(appVersionProvider),
      minSupportedVersion: config.minSupportedVersion,
      latestVersion: config.latestVersion,
    );
    if (requirement != UpdateRequirement.optional) return;
    final store = ref.read(keyValueStoreProvider);
    if (await store.getString(_dismissedVersionKey) == config.latestVersion ||
        !mounted) {
      return;
    }
    _promptOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Update available'),
          content: Text('Version ${config.latestVersion} is available.'),
          actions: [
            TextButton(
              onPressed: () async {
                await store.setString(_dismissedVersionKey, config.latestVersion);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Later'),
            ),
            if (Uri.tryParse(config.updateUrl)?.hasScheme == true)
              FilledButton(
                onPressed: () => _openUpdateUrl(config.updateUrl),
                child: const Text('Update'),
              ),
          ],
        ),
      ),
    );
    _promptOpen = false;
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOptionalIfNeeded());
    }
  }

  Future<void> _openUpdateUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appConfigControllerProvider, (previous, next) {
      final nextRequirement = UpdatePolicy.evaluate(
        currentVersion: ref.read(appVersionProvider),
        minSupportedVersion: next.minSupportedVersion,
        latestVersion: next.latestVersion,
      );
      if (nextRequirement != UpdateRequirement.optional && _promptOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _promptOpen) {
            Navigator.of(context, rootNavigator: true).pop();
            _promptOpen = false;
          }
        });
      }
      if (previous?.latestVersion != next.latestVersion ||
          previous?.minSupportedVersion != next.minSupportedVersion) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showOptionalIfNeeded());
      }
    });
    final config = ref.watch(appConfigControllerProvider);
    final requirement = UpdatePolicy.evaluate(
      currentVersion: ref.watch(appVersionProvider),
      minSupportedVersion: config.minSupportedVersion,
      latestVersion: config.latestVersion,
    );
    if (requirement == UpdateRequirement.required) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update, size: 56),
                  const SizedBox(height: 16),
                  Text('Update required', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Please update to version ${config.latestVersion} to continue.'),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: config.updateUrl.isEmpty ? null : () => _openUpdateUrl(config.updateUrl),
                    child: const Text('Update now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return const HomeScreen();
  }
}

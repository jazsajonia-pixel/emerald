import 'package:sapphire/app/app.dart';
import 'package:sapphire/data/memory_vault_storage.dart';
import 'package:sapphire/features/ai/ai_config.dart';
import 'package:sapphire/features/sync/sync_controller.dart';
import 'package:sapphire/features/sync/sync_screen.dart';
import 'package:sapphire/features/vault/vault_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpSapphire(
  WidgetTester tester, {
  MemoryVaultStorage? storage,
  Size size = const Size(360, 740),
  double textScale = 1.0,
  SecretStore? secrets,
  AiProviderFactory? aiFactory,
  GitHubClientFactory? gitHubFactory,
  GitHubAuthFactory? gitHubAuthFactory,
  UrlOpener? urlOpener,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultStorageProvider.overrideWithValue(storage ?? MemoryVaultStorage()),
        secretStoreProvider.overrideWithValue(secrets ?? MemorySecretStore()),
        if (aiFactory != null)
          aiProviderFactoryProvider.overrideWithValue(aiFactory),
        if (gitHubFactory != null)
          gitHubClientFactoryProvider.overrideWithValue(gitHubFactory),
        if (gitHubAuthFactory != null)
          gitHubAuthFactoryProvider.overrideWithValue(gitHubAuthFactory),
        urlOpenerProvider.overrideWithValue(urlOpener ?? (_) async => true),
        autoSyncRuntimeProvider.overrideWithValue(false),
      ],
      child: const SapphireApp(reduceMotion: true),
    ),
  );
  await tester.pumpAndSettle();
}

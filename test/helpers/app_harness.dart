import 'package:emerald/app/app.dart';
import 'package:emerald/data/memory_vault_storage.dart';
import 'package:emerald/features/ai/ai_config.dart';
import 'package:emerald/features/sync/sync_controller.dart';
import 'package:emerald/features/vault/vault_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpEmerald(
  WidgetTester tester, {
  MemoryVaultStorage? storage,
  Size size = const Size(360, 740),
  double textScale = 1.0,
  SecretStore? secrets,
  AiProviderFactory? aiFactory,
  GitHubClientFactory? gitHubFactory,
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
      ],
      child: const EmeraldApp(),
    ),
  );
  await tester.pumpAndSettle();
}

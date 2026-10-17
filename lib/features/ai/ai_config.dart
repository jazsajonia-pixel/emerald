import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_types.dart';
import 'providers/gemini_provider.dart';

/// Key/value store for secrets. Production uses Android Keystore-backed
/// [FlutterSecureStorage]; tests use [MemorySecretStore].
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Known provider adapters. Add new providers here (one adapter each).
class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    required this.capabilities,
    required this.keyHelp,
    required this.defaultModel,
    required this.dataNotice,
  });

  final String id;
  final String name;
  final ProviderCapabilities capabilities;
  final String keyHelp;
  final String defaultModel;
  final String dataNotice;
}

const providerCatalog = <ProviderInfo>[
  ProviderInfo(
    id: GeminiProvider.providerId,
    name: 'Google Gemini',
    capabilities: ProviderCapabilities(
      text: true,
      toolUse: true,
      streaming: false,
      listModels: true,
    ),
    keyHelp:
        'Create a key at aistudio.google.com (Google AI Studio → Get API key). '
        'A free tier with rate limits is available; paid usage is billed by '
        'Google.',
    defaultModel: 'gemini-3.8-flash',
    dataNotice:
        'Your question and the notes the AI reads are sent to Google. On the '
        'free tier Google states it may use this content to improve its '
        'products; on the paid tier it states it does not.',
  ),
];

ProviderInfo? providerInfo(String? id) {
  for (final p in providerCatalog) {
    if (p.id == id) return p;
  }
  return null;
}

class AiConfig {
  const AiConfig({
    this.loaded = false,
    this.providerId,
    this.model,
    this.hasKey = false,
    this.consented = false,
  });

  final bool loaded;
  final String? providerId;
  final String? model;
  final bool hasKey;

  /// The user acknowledged that remote AI requests send note content.
  final bool consented;

  bool get ready =>
      providerId != null && hasKey && (model?.isNotEmpty ?? false);
  ProviderInfo? get info => providerInfo(providerId);

  AiConfig copyWith({
    String? providerId,
    String? model,
    bool? hasKey,
    bool? consented,
    bool clearProvider = false,
  }) => AiConfig(
    loaded: true,
    providerId: clearProvider ? null : (providerId ?? this.providerId),
    model: clearProvider ? null : (model ?? this.model),
    hasKey: clearProvider ? false : (hasKey ?? this.hasKey),
    consented: consented ?? this.consented,
  );
}

final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

/// Builds a provider adapter from a key. Overridden in tests.
typedef AiProviderFactory = AiProvider Function(
  String providerId,
  String apiKey,
  String model,
);

final aiProviderFactoryProvider = Provider<AiProviderFactory>(
  (ref) =>
      (id, key, model) => switch (id) {
        GeminiProvider.providerId => GeminiProvider(apiKey: key, model: model),
        _ => throw AiException(AiErrorCode.notConfigured),
      },
);

final aiConfigProvider = NotifierProvider<AiConfigController, AiConfig>(
  AiConfigController.new,
);

class AiConfigController extends Notifier<AiConfig> {
  static const _kProvider = 'ai.provider';
  static const _kModel = 'ai.model';
  static const _kConsent = 'ai.consent';
  static String _kKey(String provider) => 'ai.$provider.apiKey';

  SecretStore get _store => ref.read(secretStoreProvider);

  @override
  AiConfig build() {
    Future.microtask(_load);
    return const AiConfig();
  }

  Future<void> _load() async {
    final provider = await _store.read(_kProvider);
    final model = await _store.read(_kModel);
    final consent = await _store.read(_kConsent) == 'yes';
    final key = provider == null ? null : await _store.read(_kKey(provider));
    state = AiConfig(
      loaded: true,
      providerId: providerInfo(provider) == null ? null : provider,
      model: model,
      hasKey: key != null && key.isNotEmpty,
      consented: consent,
    );
  }

  Future<void> configure({
    required String providerId,
    required String model,
    String? apiKey,
  }) async {
    await _store.write(_kProvider, providerId);
    await _store.write(_kModel, model.trim());
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await _store.write(_kKey(providerId), apiKey.trim());
    }
    final has = (await _store.read(_kKey(providerId)))?.isNotEmpty ?? false;
    state = state.copyWith(
      providerId: providerId,
      model: model.trim(),
      hasKey: has,
    );
  }

  /// Deletes the stored key and provider choice.
  Future<void> removeProvider() async {
    final p = state.providerId;
    if (p != null) await _store.delete(_kKey(p));
    await _store.delete(_kProvider);
    await _store.delete(_kModel);
    state = state.copyWith(clearProvider: true);
  }

  Future<void> setConsent(bool value) async {
    if (value) {
      await _store.write(_kConsent, 'yes');
    } else {
      await _store.delete(_kConsent);
    }
    state = state.copyWith(consented: value);
  }

  /// Creates an adapter with the stored key. The key stays inside the
  /// adapter and is never put into state.
  Future<AiProvider> createProvider({
    String? modelOverride,
    String? keyOverride,
  }) async {
    final p = state.providerId;
    if (p == null) throw AiException(AiErrorCode.notConfigured);
    final key = keyOverride ?? await _store.read(_kKey(p));
    if (key == null || key.isEmpty) {
      throw AiException(AiErrorCode.notConfigured);
    }
    return ref.read(aiProviderFactoryProvider)(
      p,
      key,
      modelOverride ?? state.model ?? '',
    );
  }

  /// Builds a temporary adapter for testing a key before saving it.
  AiProvider providerFor(String providerId, String key, String model) =>
      ref.read(aiProviderFactoryProvider)(providerId, key, model);
}

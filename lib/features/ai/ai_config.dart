import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_types.dart';
import 'providers/gemini_provider.dart';
import 'providers/openai_compatible_provider.dart';

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
    this.defaultBaseUrl,
    this.supportsReasoningEffort = false,
    this.capabilityNote,
  });

  final String id;
  final String name;
  final ProviderCapabilities capabilities;
  final String keyHelp;
  final String defaultModel;
  final String dataNotice;

  /// Non-null when the user may change the server URL.
  final String? defaultBaseUrl;
  final bool supportsReasoningEffort;
  final String? capabilityNote;

  bool get configurableBaseUrl => defaultBaseUrl != null;

  /// A key is optional only for a server on this device (e.g. local Ollama).
  bool keyRequired(String? baseUrl) {
    if (!configurableBaseUrl) return true;
    final host = Uri.tryParse(baseUrl ?? '')?.host ?? '';
    return !OpenAiCompatibleProvider.isLoopbackHost(host);
  }
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
  ProviderInfo(
    id: OpenAiCompatibleProvider.providerId,
    name: 'OpenAI-compatible',
    capabilities: ProviderCapabilities(
      text: true,
      toolUse: true,
      streaming: false,
      listModels: true,
    ),
    keyHelp:
        'For OpenAI, create a key at platform.openai.com (paid, billed per '
        'token by OpenAI). For another server that implements the OpenAI Chat '
        'Completions API, enter its base URL and key. A server on this phone '
        '(http://localhost…, e.g. Ollama in Termux) needs no key.',
    defaultModel: 'gpt-6-luna',
    defaultBaseUrl: OpenAiCompatibleProvider.defaultBaseUrl,
    supportsReasoningEffort: true,
    capabilityNote:
        'Note search and edit proposals need a model that supports function '
        'calling over Chat Completions. OpenAI documents this for gpt-6-luna '
        'only with reasoning effort "none"; GPT-6 Astra and GPT-6.1 Sol do not '
        'support it there. Other servers depend on the model.',
    dataNotice:
        'Your question and the notes the AI reads are sent to the server at the '
        'base URL. OpenAI states API data is not used for training unless you '
        'opt in, and keeps abuse-monitoring logs for up to 30 days. For other '
        'servers, check their policy; a localhost server keeps data on this '
        'phone.',
  ),
];

ProviderInfo? providerInfo(String? id) {
  for (final p in providerCatalog) {
    if (p.id == id) return p;
  }
  return null;
}

/// Everything needed to build an adapter. Holds the key only transiently.
class ProviderSettings {
  const ProviderSettings({
    required this.providerId,
    required this.apiKey,
    required this.model,
    this.baseUrl,
    this.reasoningEffort,
  });

  final String providerId;
  final String apiKey;
  final String model;
  final String? baseUrl;
  final String? reasoningEffort;

  @override
  String toString() => 'ProviderSettings($providerId, $model)';
}

class AiConfig {
  const AiConfig({
    this.loaded = false,
    this.providerId,
    this.model,
    this.baseUrl,
    this.reasoningEffort,
    this.hasKey = false,
    this.consented = false,
  });

  final bool loaded;
  final String? providerId;
  final String? model;
  final String? baseUrl;
  final String? reasoningEffort;
  final bool hasKey;

  /// The user acknowledged that remote AI requests send note content.
  final bool consented;

  bool get ready {
    final i = info;
    if (i == null || (model?.isEmpty ?? true)) return false;
    return hasKey || !i.keyRequired(baseUrl);
  }

  ProviderInfo? get info => providerInfo(providerId);
}

final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

/// Builds a provider adapter. Overridden in tests.
typedef AiProviderFactory = AiProvider Function(ProviderSettings settings);

final aiProviderFactoryProvider = Provider<AiProviderFactory>(
  (ref) =>
      (s) => switch (s.providerId) {
        GeminiProvider.providerId => GeminiProvider(
          apiKey: s.apiKey,
          model: s.model,
        ),
        OpenAiCompatibleProvider.providerId => OpenAiCompatibleProvider(
          apiKey: s.apiKey,
          model: s.model,
          baseUrl: s.baseUrl ?? OpenAiCompatibleProvider.defaultBaseUrl,
          reasoningEffort: s.reasoningEffort,
        ),
        _ => throw AiException(AiErrorCode.notConfigured),
      },
);

final aiConfigProvider = NotifierProvider<AiConfigController, AiConfig>(
  AiConfigController.new,
);

/// Stored per provider, so switching providers keeps each one's settings.
/// None of this touches the vault.
class AiConfigController extends Notifier<AiConfig> {
  static const _kProvider = 'ai.provider';
  static const _kLegacyModel = 'ai.model';
  static const _kConsent = 'ai.consent';
  static String _kKey(String p) => 'ai.$p.apiKey';
  static String _kModel(String p) => 'ai.$p.model';
  static String _kBaseUrl(String p) => 'ai.$p.baseUrl';
  static String _kReasoning(String p) => 'ai.$p.reasoningEffort';

  SecretStore get _store => ref.read(secretStoreProvider);

  @override
  AiConfig build() {
    Future.microtask(_load);
    return const AiConfig();
  }

  Future<void> _load() async {
    final provider = await _store.read(_kProvider);
    final consent = await _store.read(_kConsent) == 'yes';
    final valid = providerInfo(provider) != null;
    final cfg = valid
        ? await _readFor(provider!, consent)
        : AiConfig(loaded: true, consented: consent);
    if (ref.mounted) state = cfg;
  }

  Future<AiConfig> _readFor(String p, bool consent) async {
    final key = await _store.read(_kKey(p));
    return AiConfig(
      loaded: true,
      providerId: p,
      model:
          await _store.read(_kModel(p)) ??
          (p == GeminiProvider.providerId
              ? await _store.read(_kLegacyModel)
              : null),
      baseUrl: await _store.read(_kBaseUrl(p)),
      reasoningEffort: await _store.read(_kReasoning(p)),
      hasKey: key != null && key.isNotEmpty,
      consented: consent,
    );
  }

  /// Stored settings for [providerId] (for the settings form). No key.
  Future<AiConfig> storedFor(String providerId) =>
      _readFor(providerId, state.consented);

  Future<void> _put(String key, String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _store.delete(key);
    } else {
      await _store.write(key, value.trim());
    }
  }

  Future<void> configure({
    required String providerId,
    required String model,
    String? apiKey,
    String? baseUrl,
    String? reasoningEffort,
  }) async {
    await _store.write(_kProvider, providerId);
    await _store.write(_kModel(providerId), model.trim());
    await _put(_kBaseUrl(providerId), baseUrl);
    await _put(_kReasoning(providerId), reasoningEffort);
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await _store.write(_kKey(providerId), apiKey.trim());
    }
    state = await _readFor(providerId, state.consented);
  }

  /// Deletes the stored key and settings of the active provider.
  Future<void> removeProvider() async {
    final p = state.providerId;
    if (p != null) {
      for (final k in [_kKey(p), _kModel(p), _kBaseUrl(p), _kReasoning(p)]) {
        await _store.delete(k);
      }
    }
    await _store.delete(_kProvider);
    await _store.delete(_kLegacyModel);
    state = AiConfig(loaded: true, consented: state.consented);
  }

  Future<void> setConsent(bool value) async {
    await _put(_kConsent, value ? 'yes' : null);
    final s = state;
    state = AiConfig(
      loaded: s.loaded,
      providerId: s.providerId,
      model: s.model,
      baseUrl: s.baseUrl,
      reasoningEffort: s.reasoningEffort,
      hasKey: s.hasKey,
      consented: value,
    );
  }

  /// Creates an adapter for the active provider with its stored key. The key
  /// stays inside the adapter and is never put into state.
  Future<AiProvider> createProvider() async {
    final s = state;
    final p = s.providerId;
    if (p == null || !s.ready) throw AiException(AiErrorCode.notConfigured);
    final key = await _store.read(_kKey(p)) ?? '';
    return ref.read(aiProviderFactoryProvider)(
      ProviderSettings(
        providerId: p,
        apiKey: key,
        model: s.model ?? '',
        baseUrl: s.baseUrl,
        reasoningEffort: s.reasoningEffort,
      ),
    );
  }

  /// Builds an adapter from form values (for "Test connection"). When
  /// [apiKey] is empty, the stored key for that provider is used.
  Future<AiProvider> providerFor({
    required String providerId,
    required String model,
    String? apiKey,
    String? baseUrl,
    String? reasoningEffort,
  }) async {
    final key = (apiKey?.trim().isNotEmpty ?? false)
        ? apiKey!.trim()
        : (await _store.read(_kKey(providerId)) ?? '');
    final info = providerInfo(providerId);
    if (info == null || (key.isEmpty && info.keyRequired(baseUrl))) {
      throw AiException(AiErrorCode.notConfigured);
    }
    return ref.read(aiProviderFactoryProvider)(
      ProviderSettings(
        providerId: providerId,
        apiKey: key,
        model: model,
        baseUrl: baseUrl,
        reasoningEffort: reasoningEffort,
      ),
    );
  }
}

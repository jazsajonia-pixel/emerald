import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_config.dart';
import 'ai_types.dart';
import 'providers/openai_compatible_provider.dart';

/// Provider selection, API key entry (stored with Android Keystore-backed
/// secure storage) and model choice.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _baseUrl = TextEditingController();
  final _reasoning = TextEditingController();
  bool _keySaved = false;
  String _providerId = providerCatalog.first.id;
  bool _obscure = true;
  bool _busy = false;
  String? _status;
  bool _statusError = false;
  List<AiModelInfo> _models = const [];
  bool _initialised = false;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _baseUrl.dispose();
    _reasoning.dispose();
    super.dispose();
  }

  ProviderInfo get _info => providerInfo(_providerId)!;

  void _init(AiConfig cfg) {
    if (_initialised || !cfg.loaded) return;
    _initialised = true;
    _providerId = cfg.providerId ?? providerCatalog.first.id;
    _fill(cfg.providerId == _providerId ? cfg : null);
  }

  void _fill(AiConfig? stored) {
    _model.text = stored?.model ?? _info.defaultModel;
    _baseUrl.text = stored?.baseUrl ?? _info.defaultBaseUrl ?? '';
    _reasoning.text = stored?.reasoningEffort ?? '';
    _keySaved = stored?.hasKey ?? false;
  }

  Future<void> _switchProvider(String id) async {
    setState(() {
      _providerId = id;
      _models = const [];
      _status = null;
      _key.clear();
    });
    final stored = await ref.read(aiConfigProvider.notifier).storedFor(id);
    if (!mounted || _providerId != id) return;
    setState(
      () => _fill(stored.model == null && !stored.hasKey ? null : stored),
    );
  }

  String? get _baseUrlValue =>
      _info.configurableBaseUrl ? _baseUrl.text.trim() : null;

  String? _formError({required bool forSave}) {
    if (_info.configurableBaseUrl) {
      final err = OpenAiCompatibleProvider.validateBaseUrl(_baseUrl.text);
      if (err != null) return err;
    }
    final needsKey = _info.keyRequired(_baseUrlValue);
    if (needsKey && _key.text.trim().isEmpty && !_keySaved) {
      return 'Enter an API key first.';
    }
    if (forSave && _model.text.trim().isEmpty) return 'Enter a model name.';
    return null;
  }

  void _showStatus(String text, {required bool error}) => setState(() {
    _statusError = error;
    _status = text;
  });

  Future<void> _test() async {
    final err = _formError(forSave: false);
    if (err != null) return _showStatus(err, error: true);
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final provider = await ref
          .read(aiConfigProvider.notifier)
          .providerFor(
            providerId: _providerId,
            model: _model.text.trim(),
            apiKey: _key.text,
            baseUrl: _baseUrlValue,
            reasoningEffort: _reasoning.text,
          );
      final models = await provider.listModels();
      if (!mounted) return;
      _models = models;
      _showStatus(
        'Connection works. ${models.length} models available. '
        '(Listing models does not generate text or use generation quota.)',
        error: false,
      );
    } on AiException catch (e) {
      if (mounted) _showStatus(e.userMessage, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final err = _formError(forSave: true);
    if (err != null) return _showStatus(err, error: true);
    final key = _key.text.trim();
    await ref
        .read(aiConfigProvider.notifier)
        .configure(
          providerId: _providerId,
          model: _model.text.trim(),
          apiKey: key.isEmpty ? null : key,
          baseUrl: _baseUrlValue,
          reasoningEffort: _info.supportsReasoningEffort
              ? _reasoning.text
              : null,
        );
    _key.clear();
    if (!mounted) return;
    _keySaved = ref.read(aiConfigProvider).hasKey;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('AI provider saved')));
    _showStatus(
      'Saved. Any key is stored encrypted on this device only.',
      error: false,
    );
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove AI provider?'),
        content: const Text(
          'The stored API key is deleted from this device. Notes are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(aiConfigProvider.notifier).removeProvider();
    if (!mounted) return;
    setState(() {
      _keySaved = false;
      _fill(null);
    });
    _showStatus('Removed.', error: false);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(aiConfigProvider);
    _init(cfg);
    final caps = _info.capabilities;
    final keySaved = _keySaved;
    return Scaffold(
      appBar: AppBar(title: const Text('AI provider')),
      // Short form: a non-lazy scroll view keeps every field alive.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _providerId,
              decoration: const InputDecoration(
                labelText: 'Provider',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final p in providerCatalog)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null && v != _providerId) _switchProvider(v);
                    },
            ),
            const SizedBox(height: 8),
            Text(_info.keyHelp, style: Theme.of(context).textTheme.bodySmall),
            if (_info.configurableBaseUrl) ...[
              const SizedBox(height: 16),
              TextField(
                key: const Key('base-url-field'),
                controller: _baseUrl,
                autocorrect: false,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  helperText:
                      'OpenAI: ${_info.defaultBaseUrl}  ·  Ollama on this phone: '
                      'http://localhost:11434/v1',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('api-key-field'),
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: keySaved
                    ? 'API key (saved — enter to replace)'
                    : _info.keyRequired(_baseUrlValue)
                    ? 'API key'
                    : 'API key (optional for localhost)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show key' : 'Hide key',
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('model-field'),
              controller: _model,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Model',
                helperText: 'Use "Test connection" to list the models your key can use.',
                border: OutlineInputBorder(),
              ),
            ),
            if (_info.supportsReasoningEffort) ...[
              const SizedBox(height: 16),
              TextField(
                key: const Key('reasoning-field'),
                controller: _reasoning,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Reasoning effort (optional)',
                  helperText:
                      'Sent as reasoning_effort only if set, e.g. "none" for '
                      'gpt-6-luna tool use. Leave empty for other servers.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_models.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in _models.take(30))
                    ChoiceChip(
                      label: Text(m.id),
                      selected: _model.text == m.id,
                      onSelected: (_) => setState(() => _model.text = m.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _test,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test connection'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
                if (cfg.providerId == _providerId)
                  TextButton.icon(
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove key'),
                  ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                style: TextStyle(
                  color: _statusError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
            const Divider(height: 32),
            Text(
              'What this provider supports in Sapphire',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            _cap('Text answers', caps.text),
            _cap('Tool use (search/read notes, propose edits)', caps.toolUse),
            _cap('Streaming replies', caps.streaming, note: 'not used yet'),
            _cap('Model listing', caps.listModels),
            if (_info.capabilityNote != null)
              Text(
                _info.capabilityNote!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const Divider(height: 32),
            Text(
              'Privacy and cost',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(_info.dataNotice),
            const SizedBox(height: 8),
            const Text(
              'The key is stored encrypted with Android Keystore on this device. '
              'It is never written to your vault, never shown again after saving, '
              'and never logged. Requests go directly from your phone to the '
              'provider; there is no Sapphire server.',
            ),
            if (cfg.consented)
              TextButton(
                onPressed: () =>
                    ref.read(aiConfigProvider.notifier).setConsent(false),
                child: const Text('Ask me again before sending notes'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cap(String label, bool ok, {String? note}) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      ok ? Icons.check : Icons.remove,
      color: ok ? Theme.of(context).colorScheme.primary : null,
    ),
    title: Text(label),
    subtitle: !ok && note != null ? Text(note) : null,
  );
}

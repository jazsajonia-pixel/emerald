import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_config.dart';
import 'ai_types.dart';

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
    super.dispose();
  }

  ProviderInfo get _info => providerInfo(_providerId)!;

  void _init(AiConfig cfg) {
    if (_initialised || !cfg.loaded) return;
    _initialised = true;
    _providerId = cfg.providerId ?? providerCatalog.first.id;
    _model.text = cfg.model ?? _info.defaultModel;
  }

  Future<void> _test(AiConfig cfg) async {
    final key = _key.text.trim();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final notifier = ref.read(aiConfigProvider.notifier);
      final provider = key.isNotEmpty
          ? notifier.providerFor(_providerId, key, _model.text.trim())
          : await notifier.createProvider(modelOverride: _model.text.trim());
      final models = await provider.listModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _statusError = false;
        _status =
            'Connection works. ${models.length} chat models available. '
            '(Listing models does not use generation quota.)';
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = true;
        _status = e.userMessage;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(AiConfig cfg) async {
    final key = _key.text.trim();
    if (key.isEmpty && !(cfg.hasKey && cfg.providerId == _providerId)) {
      setState(() {
        _statusError = true;
        _status = 'Enter an API key first.';
      });
      return;
    }
    if (_model.text.trim().isEmpty) {
      setState(() {
        _statusError = true;
        _status = 'Enter a model name.';
      });
      return;
    }
    await ref
        .read(aiConfigProvider.notifier)
        .configure(
          providerId: _providerId,
          model: _model.text.trim(),
          apiKey: key.isEmpty ? null : key,
        );
    _key.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('AI provider saved')));
    setState(() {
      _statusError = false;
      _status = 'Saved. The key is stored encrypted on this device only.';
    });
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
    if (mounted) setState(() => _status = 'Removed.');
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(aiConfigProvider);
    _init(cfg);
    final caps = _info.capabilities;
    final keySaved = cfg.hasKey && cfg.providerId == _providerId;
    return Scaffold(
      appBar: AppBar(title: const Text('AI provider')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _providerId,
            decoration: const InputDecoration(
              labelText: 'Provider',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in providerCatalog)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() {
              _providerId = v ?? _providerId;
              _model.text = _info.defaultModel;
              _models = const [];
            }),
          ),
          const SizedBox(height: 8),
          Text(_info.keyHelp, style: Theme.of(context).textTheme.bodySmall),
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
                  : 'API key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show key' : 'Hide key',
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
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
              helperText:
                  'Use "Test connection" to list the models your key can use.',
              border: OutlineInputBorder(),
            ),
          ),
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
                onPressed: _busy ? null : () => _test(cfg),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Test connection'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _save(cfg),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
              if (cfg.providerId != null)
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
            'What this provider supports in Emerald',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          _cap('Text answers', caps.text),
          _cap('Tool use (search/read notes, propose edits)', caps.toolUse),
          _cap('Streaming replies', caps.streaming, note: 'not used yet'),
          _cap('Model listing', caps.listModels),
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
            'provider; there is no Emerald server.',
          ),
          if (cfg.consented)
            TextButton(
              onPressed: () =>
                  ref.read(aiConfigProvider.notifier).setConsent(false),
              child: const Text('Ask me again before sending notes'),
            ),
        ],
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

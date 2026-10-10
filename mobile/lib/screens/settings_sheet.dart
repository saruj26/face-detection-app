import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_config.dart';
import '../providers/providers.dart';
import '../services/glasses_api.dart';

/// Lets the user point the app at their backend (emulator vs. phone on LAN).
class SettingsSheet extends ConsumerStatefulWidget {
  const SettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const SettingsSheet(),
      );

  @override
  ConsumerState<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<SettingsSheet> {
  late final TextEditingController _url =
      TextEditingController(text: ref.read(apiBaseUrlProvider));
  String? _status;
  bool _testing = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    if (!ApiConfig.isValid(_url.text)) {
      setState(() => _status = 'Enter a URL like http://192.168.1.20:8000');
      return;
    }
    setState(() {
      _testing = true;
      _status = null;
    });
    final dio = GlassesApi.createDio(ApiConfig.normalize(_url.text));
    try {
      final ok = await GlassesApi(dio).checkHealth();
      _status = ok ? '✓ Connected. API and database are healthy.' : 'Server responded but is not healthy.';
    } on ApiException catch (e) {
      _status = e.message;
    } finally {
      dio.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!ApiConfig.isValid(_url.text)) {
      setState(() => _status = 'Enter a URL like http://192.168.1.20:8000');
      return;
    }
    await ref.read(apiBaseUrlProvider.notifier).set(_url.text);
    ref.invalidate(catalogueProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Catalogue server', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Optional. Without a server the app uses its built-in frames.\n'
            'Android emulator: http://10.0.2.2:8000\n'
            'Phone on the same Wi-Fi: http://<computer IP>:8000',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'API base URL',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Test connection'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: _save, child: const Text('Save'))),
            ],
          ),
          TextButton(
            onPressed: () async {
              await ref.read(apiBaseUrlProvider.notifier).resetToDefault();
              ref.invalidate(catalogueProvider);
              _url.text = ref.read(apiBaseUrlProvider);
            },
            child: Text(
              ApiConfig.hasBackend(ApiConfig.defaultBaseUrl)
                  ? 'Reset to default (${ApiConfig.defaultBaseUrl})'
                  : 'Use built-in catalogue (no server)',
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/glasses.dart';
import '../providers/providers.dart';
import '../widgets/glasses_card.dart';
import 'glasses_detail_screen.dart';

class CatalogueScreen extends ConsumerStatefulWidget {
  const CatalogueScreen({super.key});

  @override
  ConsumerState<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends ConsumerState<CatalogueScreen> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(catalogueProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Eyeglass catalogue')),
      body: switch (catalogue) {
        AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.refresh(catalogueProvider.future),
            child: _buildGrid(context, value.items, value.isOffline, value.offlineReason),
          ),
        AsyncError(:final error) => CatalogueError(
            message: error.toString(),
            onRetry: () => ref.invalidate(catalogueProvider),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildGrid(BuildContext context, List<Glasses> items, bool offline, String? reason) {
    final categories = {for (final g in items) g.category}.toList()..sort();
    final visible = _category == null ? items : items.where((g) => g.category == _category).toList();
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Only warn when a configured server could not be reached.
        if (offline && reason != null) SliverToBoxAdapter(child: OfflineBanner(reason: reason)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _chip('All', _category == null, () => setState(() => _category = null)),
                for (final c in categories)
                  _chip(c, _category == c, () => setState(() => _category = c)),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No frames in this category yet.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.98,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) => GlassesCard(
                glasses: visible[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GlassesDetailScreen(initial: visible[i]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_outlined, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Couldn't reach the catalogue server, so the built-in frames are shown. "
              'Pull down to retry.\n${reason ?? ''}',
              style: TextStyle(color: scheme.onTertiaryContainer, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogueError extends StatelessWidget {
  const CatalogueError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

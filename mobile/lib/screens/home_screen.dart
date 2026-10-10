import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_config.dart';
import '../core/theme.dart';
import '../models/glasses.dart';
import '../providers/providers.dart';
import '../widgets/glasses_image.dart';
import 'settings_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalogue = ref.watch(catalogueProvider);
    final featured = switch (catalogue) {
      AsyncData(:final value) => value.items.take(6).toList(),
      _ => const <Glasses>[],
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/branding/logo.png', width: 34, height: 34),
            ),
            const SizedBox(width: 10),
            const Text('Frame Finder', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          // Server settings are for development; shared builds without a
          // server hide them.
          if (!kReleaseMode || ApiConfig.hasBackend(ApiConfig.defaultBaseUrl))
            IconButton(
              tooltip: 'Server settings',
              onPressed: () => SettingsSheet.show(context),
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: brandGradient,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Try glasses on\nbefore you buy',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your face is detected on your phone. Photos are never uploaded.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF3D5AFE),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => openTryOn(ref),
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Start live try-on'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => openTryOn(ref, launch: TryOnLaunch.pickPhoto),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Upload a photo'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Featured frames', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => ref.read(navigationProvider.notifier).go(AppTab.catalogue),
                child: const Text('See all'),
              ),
            ],
          ),
          SizedBox(
            height: 150,
            child: catalogue.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: featured.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final g = featured[i];
                      return SizedBox(
                        width: 170,
                        child: Card(
                          child: InkWell(
                            onTap: () => openTryOn(ref, glasses: g),
                            child: Column(
                              children: [
                                AspectRatio(
                                  aspectRatio: productImageAspect,
                                  child: GlassesImage(g.catalogueImageUrl, fit: BoxFit.cover),
                                ),
                                Expanded(
                                  child: Center(
                                    child: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 24),
          Text('How it works', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _InfoTile(
            icon: Icons.center_focus_strong_outlined,
            title: 'Face detection',
            body: 'Google ML Kit finds your face and eye landmarks on the device, '
                'in each camera frame or in your photo. It locates a face; it does not '
                'identify who you are.',
          ),
          const _InfoTile(
            icon: Icons.layers_outlined,
            title: '2D virtual try-on',
            body: 'A transparent picture of the frame is scaled, rotated and positioned '
                'from your eye positions and head tilt. It is a geometric overlay, not a '
                'trained AI model, and it is an approximation, not a fitting measurement.',
          ),
          const _InfoTile(
            icon: Icons.face_outlined,
            title: 'Face-shape classification (not included)',
            body: 'Assigning a face shape (oval, round, square…) is a separate task. '
                'This app does not do it. A reliable version would need a model trained '
                'and validated for it, and landmark-based rules would only be rough hints.',
          ),
          const _InfoTile(
            icon: Icons.warning_amber_outlined,
            title: 'Limitations',
            body: 'Works best facing the camera. The overlay hides when you turn or tilt '
                'too far, because a flat image cannot show side views or the temples going '
                'behind your ears. Hair and hands are not drawn in front of the frame '
                '(no occlusion). Realistic 3D try-on is a planned future enhancement.',
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(body, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fit_adjustment.dart';
import '../providers/providers.dart';

/// Optional manual size/position fine-tuning on top of the automatic fit.
class AdjustPanel extends ConsumerWidget {
  const AdjustPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adj = ref.watch(fitAdjustmentProvider);
    final notifier = ref.read(fitAdjustmentProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Adjust fit', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton(
                  onPressed: adj.isIdentity ? null : notifier.reset,
                  child: const Text('Reset'),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            _SliderRow(
              icon: Icons.open_in_full,
              label: 'Size',
              value: adj.scale,
              min: FitAdjustment.minScale,
              max: FitAdjustment.maxScale,
              display: '${(adj.scale * 100).round()}%',
              onChanged: (v) => notifier.update(adj.copyWith(scale: v)),
            ),
            _SliderRow(
              icon: Icons.swap_vert,
              label: 'Up / down',
              value: adj.offsetY,
              min: -FitAdjustment.maxOffsetY,
              max: FitAdjustment.maxOffsetY,
              display: adj.offsetY.toStringAsFixed(2),
              onChanged: (v) => notifier.update(adj.copyWith(offsetY: v)),
            ),
            _SliderRow(
              icon: Icons.swap_horiz,
              label: 'Left / right',
              value: adj.offsetX,
              min: -FitAdjustment.maxOffsetX,
              max: FitAdjustment.maxOffsetX,
              display: adj.offsetX.toStringAsFixed(2),
              onChanged: (v) => notifier.update(adj.copyWith(offsetX: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        SizedBox(width: 84, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
            semanticFormatterCallback: (_) => '$label $display',
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(display, textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelSmall),
        ),
      ],
    );
  }
}

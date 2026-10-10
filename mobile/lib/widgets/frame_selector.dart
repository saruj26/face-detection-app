import 'package:flutter/material.dart';

import '../models/glasses.dart';
import 'glasses_image.dart';

/// Horizontal strip of frames for switching glasses during try-on.
class FrameSelector extends StatelessWidget {
  const FrameSelector({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<Glasses> items;
  final Glasses? selected;
  final ValueChanged<Glasses> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final g = items[i];
          final isSelected = g.id == selected?.id;
          return Semantics(
            selected: isSelected,
            button: true,
            label: '${g.name}, ${g.formattedPrice}',
            child: GestureDetector(
              onTap: () => onSelected(g),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 108,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? scheme.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(child: GlassesImage(g.overlayImageUrl)),
                    const SizedBox(height: 2),
                    Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      g.formattedPrice,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

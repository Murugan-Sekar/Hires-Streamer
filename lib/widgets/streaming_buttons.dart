import 'package:flutter/material.dart';

enum StreamingButtonVariant {
  compact, // Used in Home tab sections
  large, // Used in detail page headers
}

class StreamingButtons extends StatelessWidget {
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final StreamingButtonVariant variant;
  final Color? color;

  const StreamingButtons({
    super.key,
    this.onPlay,
    this.onShuffle,
    this.variant = StreamingButtonVariant.compact,
    this.color,
  });

  const StreamingButtons.compact({
    Key? key,
    VoidCallback? onPlay,
    VoidCallback? onShuffle,
    Color? color,
  }) : this(
         key: key,
         onPlay: onPlay,
         onShuffle: onShuffle,
         variant: StreamingButtonVariant.compact,
         color: color,
       );

  const StreamingButtons.large({
    Key? key,
    VoidCallback? onPlay,
    VoidCallback? onShuffle,
    Color? color,
  }) : this(
         key: key,
         onPlay: onPlay,
         onShuffle: onShuffle,
         variant: StreamingButtonVariant.large,
         color: color,
       );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = color ?? colorScheme.primary;

    if (variant == StreamingButtonVariant.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCompactButton(
            context,
            icon: Icons.play_arrow_rounded,
            onPressed: onPlay,
            color: primaryColor,
            tooltip: 'Play',
          ),
          const SizedBox(width: 8),
          _buildCompactButton(
            context,
            icon: Icons.shuffle_rounded,
            onPressed: onShuffle,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
            iconColor: colorScheme.onSurfaceVariant,
            onPressedColor: primaryColor,
            tooltip: 'Shuffle',
          ),
        ],
      );
    }

    // Large variant for Detail Headers
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLargePlayButton(context, primaryColor),
        const SizedBox(width: 16),
        _buildLargeCircleButton(
          context,
          icon: Icons.shuffle_rounded,
          onPressed: onShuffle,
          tooltip: 'Shuffle',
        ),
      ],
    );
  }

  Widget _buildCompactButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
    Color? iconColor,
    Color? onPressedColor,
    required String tooltip,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: iconColor ?? Colors.white),
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          splashRadius: 16,
        ),
      ),
    );
  }

  Widget _buildLargePlayButton(BuildContext context, Color primaryColor) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Play',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLargeCircleButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 26, color: colorScheme.primary),
          tooltip: tooltip,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

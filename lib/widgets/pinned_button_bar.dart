import 'package:flutter/material.dart';
import 'package:hires_streamer/widgets/streaming_buttons.dart';

/// A pinned sliver that keeps Play / Shuffle buttons visible during scrolling.
///
/// Place this immediately after the [StreamingHeader] `SliverAppBar` inside a
/// `CustomScrollView`.  The buttons remain anchored below the collapsed toolbar
/// and never scroll out of view.
class PinnedButtonBar extends StatelessWidget {
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  const PinnedButtonBar({
    super.key,
    this.onPlay,
    this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedButtonBarDelegate(
        onPlay: onPlay,
        onShuffle: onShuffle,
      ),
    );
  }
}

class _PinnedButtonBarDelegate extends SliverPersistentHeaderDelegate {
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  _PinnedButtonBarDelegate({
    this.onPlay,
    this.onShuffle,
  });

  static const double _height = 72.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        // Subtle bottom border when the bar is overlapping scrolled content
        border: overlapsContent
            ? Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              )
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          StreamingButtons(
            onPlay: onPlay,
            onShuffle: onShuffle,
            variant: StreamingButtonVariant.large,
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedButtonBarDelegate oldDelegate) =>
      onPlay != oldDelegate.onPlay || onShuffle != oldDelegate.onShuffle;
}

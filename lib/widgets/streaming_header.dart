import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hires_streamer/services/cover_cache_manager.dart';

/// A collapsing header with a full-bleed background image, smooth parallax
/// animation, gradient overlay, and title crossfade.
///
/// Play / Shuffle buttons are intentionally **not** included here.  Place a
/// [PinnedButtonBar] sliver immediately after this one in your
/// `CustomScrollView.slivers` list so the buttons stay visible during scroll.
class StreamingHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final List<Widget>? actions;
  final double expandedHeight;
  final Widget? bottom;
  final IconData? fallbackIcon;

  const StreamingHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.actions,
    this.expandedHeight = 380,
    this.bottom,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.paddingOf(context).top;
    final collapsedHeight = kToolbarHeight + topPadding;

    final hasValidImage = imageUrl != null &&
        imageUrl!.isNotEmpty &&
        Uri.tryParse(imageUrl!)?.hasAuthority == true;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: true,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      actions: actions,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final double currentHeight = constraints.maxHeight;
          // t = 1.0 (fully expanded), t = 0.0 (fully collapsed)
          final double t = ((currentHeight - collapsedHeight) /
                  (expandedHeight - collapsedHeight))
              .clamp(0.0, 1.0);

          // Ease the value for smoother transitions
          final double tEased = Curves.easeOut.transform(t);

          return FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            stretchModes: const [
              StretchMode.zoomBackground,
              StretchMode.blurBackground,
            ],
            background: Stack(
              fit: StackFit.expand,
              children: [
                // ── Background image / placeholder ──
                if (hasValidImage)
                  CachedNetworkImage(
                    imageUrl: imageUrl!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    memCacheWidth: 800,
                    cacheManager: CoverCacheManager.instance,
                    placeholder: (context, url) =>
                        Container(color: colorScheme.surfaceContainerHighest),
                    errorWidget: (context, url, error) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        fallbackIcon ?? Icons.music_note,
                        size: 80,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      fallbackIcon ?? Icons.music_note,
                      size: 80,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                // ── Gradient overlay — smoothly transitions to surface ──
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 80),
                  opacity: t.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.05),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.75),
                          colorScheme.surface,
                        ],
                        stops: const [0.0, 0.35, 0.6, 0.85, 1.0],
                      ),
                    ),
                  ),
                ),

                // ── Surface fill when collapsed (prevents flicker) ──
                Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Container(color: colorScheme.surface),
                ),

                // ── Title / subtitle over the image ──
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Opacity(
                    opacity: tEased.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, (1 - tEased) * 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 32 * t.clamp(0.8, 1.0),
                              shadows: [
                                Shadow(
                                  offset: const Offset(0, 2),
                                  blurRadius: 8,
                                  color:
                                      Colors.black.withValues(alpha: 0.5),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                color:
                                    Colors.white.withValues(alpha: 0.9),
                                shadows: [
                                  Shadow(
                                    offset: const Offset(0, 1),
                                    blurRadius: 4,
                                    color: Colors.black
                                        .withValues(alpha: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Mini title in collapsed toolbar ──
                Positioned(
                  top: topPadding,
                  left: 56,
                  right: 16,
                  height: kToolbarHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Text(
                        title,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

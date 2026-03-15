import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hires_streamer/providers/local_library_provider.dart';
import 'package:hires_streamer/services/platform_bridge.dart';
import 'package:hires_streamer/utils/file_access.dart';
import 'package:hires_streamer/l10n/l10n.dart';
import 'package:hires_streamer/models/track.dart';
import 'package:hires_streamer/providers/download_queue_provider.dart';
import 'package:hires_streamer/providers/playback_provider.dart';
import 'package:hires_streamer/providers/settings_provider.dart';
import 'package:hires_streamer/providers/recent_access_provider.dart';
import 'package:hires_streamer/widgets/track_collection_quick_actions.dart';
import 'package:hires_streamer/widgets/download_service_picker.dart';
import 'package:hires_streamer/widgets/streaming_header.dart';
import 'package:hires_streamer/widgets/pinned_button_bar.dart';
import 'package:hires_streamer/utils/clickable_metadata.dart';

class _AlbumCache {
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _ttl = Duration(minutes: 10);

  static List<Track>? get(String albumId) {
    final entry = _cache[albumId];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(albumId);
      return null;
    }
    return entry.tracks;
  }

  static void set(String albumId, List<Track> tracks) {
    _cache[albumId] = _CacheEntry(tracks, DateTime.now().add(_ttl));
  }
}

class _CacheEntry {
  final List<Track> tracks;
  final DateTime expiresAt;
  _CacheEntry(this.tracks, this.expiresAt);
}

class AlbumScreen extends ConsumerStatefulWidget {
  final String albumId;
  final String albumName;
  final String? coverUrl;
  final List<Track>? tracks;
  final String? extensionId;
  final String? artistId;
  final String? artistName;

  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.albumName,
    this.coverUrl,
    this.tracks,
    this.extensionId,
    this.artistId,
    this.artistName,
  });

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  List<Track>? _tracks;
  bool _isLoading = false;
  String? _error;
  bool _showTitleInAppBar = false;
  String? _artistId;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use extensionId if available, otherwise detect from albumId prefix
      final providerId =
          widget.extensionId ??
          (widget.albumId.startsWith('deezer:') ? 'deezer' : 'spotify');
      ref
          .read(recentAccessProvider.notifier)
          .recordAlbumAccess(
            id: widget.albumId,
            name: widget.albumName,
            artistName: widget.tracks?.firstOrNull?.artistName,
            imageUrl: widget.coverUrl,
            providerId: providerId,
          );
    });

    if (widget.tracks != null && widget.tracks!.isNotEmpty) {
      _tracks = widget.tracks;
    } else {
      _tracks = _AlbumCache.get(widget.albumId);
    }
    _artistId = widget.artistId;

    if (_tracks == null || _tracks!.isEmpty) {
      _fetchTracks();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final expandedHeight = _calculateExpandedHeight(context);
    final shouldShow =
        _scrollController.offset > (expandedHeight - kToolbarHeight - 20);
    if (shouldShow != _showTitleInAppBar) {
      setState(() => _showTitleInAppBar = shouldShow);
    }
  }

  double _calculateExpandedHeight(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    return (mediaSize.height * 0.55).clamp(360.0, 520.0);
  }

  /// Upgrade cover URL to a reasonable resolution for full-screen display.
  /// Spotify CDN only has 300, 640, ~2000 — we stay at 640 (no intermediate).
  /// Deezer CDN: upgrade to 1000x1000 (available: 56, 250, 500, 1000, 1400, 1800).
  String? _highResCoverUrl(String? url) {
    if (url == null) return null;
    // Spotify CDN: upgrade 300 → 640 only (no intermediate between 640 and 2000)
    if (url.contains('ab67616d00001e02')) {
      return url.replaceAll('ab67616d00001e02', 'ab67616d0000b273');
    }
    // Deezer CDN: upgrade to 1000x1000
    final deezerRegex = RegExp(r'/(\d+)x(\d+)-(\d+)-(\d+)-(\d+)-(\d+)\.jpg$');
    if (url.contains('cdn-images.dzcdn.net') && deezerRegex.hasMatch(url)) {
      return url.replaceAllMapped(
        deezerRegex,
        (m) => '/1000x1000-${m[3]}-${m[4]}-${m[5]}-${m[6]}.jpg',
      );
    }
    return url;
  }


  Future<void> _fetchTracks() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> metadata;

      if (widget.albumId.startsWith('deezer:')) {
        final deezerAlbumId = widget.albumId.replaceFirst('deezer:', '');
        metadata = await PlatformBridge.getDeezerMetadata(
          'album',
          deezerAlbumId,
        );
      } else {
        final url = 'https://open.spotify.com/album/${widget.albumId}';
        metadata = await PlatformBridge.getSpotifyMetadataWithFallback(url);
      }

      final trackList = metadata['track_list'] as List<dynamic>;
      final tracks = trackList
          .map((t) => _parseTrack(t as Map<String, dynamic>))
          .toList();

      final albumInfo = metadata['album_info'] as Map<String, dynamic>?;
      final artistId = (albumInfo?['artist_id'] ?? albumInfo?['artistId'])
          ?.toString();

      _AlbumCache.set(widget.albumId, tracks);

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _artistId = artistId;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Track _parseTrack(Map<String, dynamic> data) {
    return Track(
      id: data['spotify_id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      artistName: data['artists'] as String? ?? '',
      albumName: data['album_name'] as String? ?? '',
      albumArtist: data['album_artist'] as String?,
      artistId:
          (data['artist_id'] ?? data['artistId'])?.toString() ?? _artistId,
      albumId: data['album_id']?.toString() ?? widget.albumId,
      coverUrl: data['images'] as String?,
      isrc: data['isrc'] as String?,
      duration: ((data['duration_ms'] as int? ?? 0) / 1000).round(),
      trackNumber: data['track_number'] as int?,
      discNumber: data['disc_number'] as int?,
      releaseDate: data['release_date'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tracks = _tracks ?? [];
    final pageBackgroundColor = colorScheme.surface;

    return Scaffold(
      backgroundColor: pageBackgroundColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildAppBar(context, colorScheme),
          PinnedButtonBar(
            onPlay: _tracks == null || _tracks!.isEmpty
                ? null
                : () => ref.read(playbackProvider.notifier).playTrackList(
                      _tracks!,
                      shuffle: false,
                    ),
            onShuffle: _tracks == null || _tracks!.isEmpty ? null : _shufflePlayLocal,
          ),
          _buildInfoCard(context, colorScheme),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildErrorWidget(_error!, colorScheme),
              ),
            ),
          if (!_isLoading && _error == null && tracks.isNotEmpty) ...[
            _buildTrackList(context, colorScheme, tracks),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme colorScheme) {
    final expandedHeight = _calculateExpandedHeight(context);
    final imageUrl = _highResCoverUrl(widget.coverUrl) ?? widget.coverUrl;

    String? subtitle;
    if (_tracks != null && _tracks!.isNotEmpty) {
      subtitle = context.l10n.tracksCount(_tracks!.length);
    }

    return StreamingHeader(
      title: widget.albumName,
      subtitle: subtitle,
      imageUrl: imageUrl,
      expandedHeight: expandedHeight,
      fallbackIcon: Icons.album,
      actions: [
        if (_tracks != null && _tracks!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () => _downloadAll(context),
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Download All',
            ),
          ),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context, ColorScheme colorScheme) {
    // Info is now displayed in the full-screen cover overlay
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  Widget _buildTrackList(
    BuildContext context,
    ColorScheme colorScheme,
    List<Track> tracks,
  ) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final track = tracks[index];
        return KeyedSubtree(
          key: ValueKey(track.id),
          child: _AlbumTrackItem(
            track: track,
            tracksList: tracks,
            onDownload: () => _downloadTrack(context, track),
          ),
        );
      }, childCount: tracks.length),
    );
  }

  void _downloadTrack(BuildContext context, Track track) {
    final settings = ref.read(settingsProvider);
    if (settings.askQualityBeforeDownload) {
      DownloadServicePicker.show(
        context,
        trackName: track.name,
        artistName: track.artistName,
        coverUrl: track.coverUrl,
        onSelect: (quality, service) {
          ref
              .read(downloadQueueProvider.notifier)
              .addToQueue(track, service, qualityOverride: quality);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.snackbarAddedToQueue(track.name)),
            ),
          );
        },
      );
    } else {
      ref
          .read(downloadQueueProvider.notifier)
          .addToQueue(track, settings.defaultService);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.snackbarAddedToQueue(track.name))),
      );
    }
  }

  void _downloadAll(BuildContext context) {
    final tracks = _tracks;
    if (tracks == null || tracks.isEmpty) return;
    final settings = ref.read(settingsProvider);
    if (settings.askQualityBeforeDownload) {
      DownloadServicePicker.show(
        context,
        trackName: '${tracks.length} tracks',
        artistName: widget.albumName,
        onSelect: (quality, service) {
          ref
              .read(downloadQueueProvider.notifier)
              .addMultipleToQueue(tracks, service, qualityOverride: quality);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.snackbarAddedTracksToQueue(tracks.length),
              ),
            ),
          );
        },
      );
    } else {
      ref
          .read(downloadQueueProvider.notifier)
          .addMultipleToQueue(tracks, settings.defaultService);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.snackbarAddedTracksToQueue(tracks.length)),
        ),
      );
    }
  }


  void _shufflePlayLocal() {
    if (_tracks == null || _tracks!.isEmpty) return;
    final startIndex = Random().nextInt(_tracks!.length);
    final messenger = ScaffoldMessenger.of(context);
    ref.read(playbackProvider.notifier).playTrackList(
          _tracks!,
          startIndex: startIndex,
          shuffle: true,
        ).catchError((e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Cannot shuffle play tracks: $e')),
      );
    });
  }

  Widget _buildErrorWidget(String error, ColorScheme colorScheme) {
    final isRateLimit =
        error.contains('429') ||
        error.toLowerCase().contains('rate limit') ||
        error.toLowerCase().contains('too many requests');

    if (isRateLimit) {
      return Card(
        elevation: 0,
        color: colorScheme.errorContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.timer_off, color: colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.errorRateLimited,
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.errorRateLimitedMessage,
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: colorScheme.errorContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(error, style: TextStyle(color: colorScheme.error)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumTrackItem extends ConsumerWidget {
  final Track track;
  final List<Track> tracksList;
  final VoidCallback onDownload;

  const _AlbumTrackItem({
    required this.track,
    required this.tracksList,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final queueItem = ref.watch(
      downloadQueueLookupProvider.select(
        (lookup) => lookup.byTrackId[track.id],
      ),
    );

    final isInHistory = ref.watch(
      downloadHistoryProvider.select((state) {
        return state.isDownloaded(track.id);
      }),
    );

    final showLocalLibraryIndicator = ref.watch(
      settingsProvider.select(
        (s) => s.localLibraryEnabled && s.localLibraryShowDuplicates,
      ),
    );
    final isInLocalLibrary = showLocalLibraryIndicator
        ? ref.watch(
            localLibraryProvider.select(
              (state) => state.existsInLibrary(
                isrc: track.isrc,
                trackName: track.name,
                artistName: track.artistName,
              ),
            ),
          )
        : false;

    final isQueued = queueItem != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        elevation: 0,
        color: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: SizedBox(
            width: 32,
            child: Center(
              child: Text(
                '${track.trackNumber ?? 0}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          title: Text(
            track.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Row(
            children: [
              Flexible(
                child: ClickableArtistName(
                  artistName: track.artistName,
                  artistId: track.artistId,
                  coverUrl: track.coverUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
              if (isInLocalLibrary) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 10,
                        color: colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        context.l10n.libraryInLibrary,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          trailing: TrackCollectionQuickActions(track: track),
          onTap: () => _handleTap(
            context,
            ref,
            isQueued: isQueued,
            isInHistory: isInHistory,
            isInLocalLibrary: isInLocalLibrary,
          ),
          onLongPress: () => TrackCollectionQuickActions.showTrackOptionsSheet(
            context,
            ref,
            track,
          ),
        ),
      ),
    );
  }

  void _handleTap(
    BuildContext context,
    WidgetRef ref, {
    required bool isQueued,
    required bool isInHistory,
    required bool isInLocalLibrary,
  }) async {
    if (isQueued) return;

    if (isInLocalLibrary) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarAlreadyInLibrary(track.name)),
          ),
        );
      }
      return;
    }

    final settings = ref.read(settingsProvider);
    if (settings.interactionMode == 'stream') {
      if (tracksList.isNotEmpty) {
        final index = tracksList.indexWhere((t) => t.id == track.id);
        if (index != -1) {
          ref
              .read(playbackProvider.notifier)
              .playTrackList(tracksList, startIndex: index);
          return;
        }
      }

      // Fallback if track list isn't ready or track isn't found
      ref.read(playbackProvider.notifier).playTrackList([track], startIndex: 0);
      return;
    }

    if (isInHistory) {
      final historyItem = ref
          .read(downloadHistoryProvider.notifier)
          .getBySpotifyId(track.id);
      if (historyItem != null) {
        final exists = await fileExists(historyItem.filePath);
        if (exists) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.snackbarAlreadyDownloaded(track.name),
                ),
              ),
            );
          }
          return;
        } else {
          ref
              .read(downloadHistoryProvider.notifier)
              .removeBySpotifyId(track.id);
        }
      }
    }

    onDownload();
  }
}

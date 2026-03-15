import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hires_streamer/services/cover_cache_manager.dart';
import 'package:hires_streamer/services/platform_bridge.dart';
import 'package:hires_streamer/l10n/l10n.dart';
import 'package:hires_streamer/models/track.dart';
import 'package:hires_streamer/providers/download_queue_provider.dart';
import 'package:hires_streamer/utils/file_access.dart';
import 'package:hires_streamer/providers/settings_provider.dart';
import 'package:hires_streamer/providers/local_library_provider.dart';
import 'package:hires_streamer/providers/playback_provider.dart';
import 'package:hires_streamer/widgets/download_service_picker.dart';
import 'package:hires_streamer/widgets/track_collection_quick_actions.dart';
import 'package:hires_streamer/widgets/streaming_header.dart';
import 'package:hires_streamer/widgets/pinned_button_bar.dart';

class PlaylistScreen extends ConsumerStatefulWidget {
  final String playlistName;
  final String? coverUrl;
  final List<Track> tracks;
  final String? playlistId;

  const PlaylistScreen({
    super.key,
    required this.playlistName,
    this.coverUrl,
    required this.tracks,
    this.playlistId,
  });

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  bool _showTitleInAppBar = false;
  final ScrollController _scrollController = ScrollController();
  List<Track>? _fetchedTracks;
  bool _isLoading = false;
  String? _error;

  List<Track> get _tracks => _fetchedTracks ?? widget.tracks;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchTracksIfNeeded();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTracksIfNeeded() async {
    if (widget.tracks.isNotEmpty || widget.playlistId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Extract numeric ID from "deezer:123" format
      String playlistId = widget.playlistId!;
      if (playlistId.startsWith('deezer:')) {
        playlistId = playlistId.substring(7);
      }

      final result = await PlatformBridge.getDeezerMetadata(
        'playlist',
        playlistId,
      );
      if (!mounted) return;

      // Go backend returns 'track_list' not 'tracks'
      final trackList = result['track_list'] as List<dynamic>? ?? [];
      final tracks = trackList
          .map((t) => _parseTrack(t as Map<String, dynamic>))
          .toList();

      setState(() {
        _fetchedTracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Track _parseTrack(Map<String, dynamic> data) {
    int durationMs = 0;
    final durationValue = data['duration_ms'];
    if (durationValue is int) {
      durationMs = durationValue;
    } else if (durationValue is double) {
      durationMs = durationValue.toInt();
    }

    return Track(
      id: (data['spotify_id'] ?? data['id'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      artistName: (data['artists'] ?? data['artist'] ?? '').toString(),
      albumName: (data['album_name'] ?? data['album'] ?? '').toString(),
      albumArtist: data['album_artist']?.toString(),
      artistId: (data['artist_id'] ?? data['artistId'])?.toString(),
      albumId: data['album_id']?.toString(),
      coverUrl: (data['cover_url'] ?? data['images'])?.toString(),
      isrc: data['isrc']?.toString(),
      duration: (durationMs / 1000).round(),
      trackNumber: data['track_number'] as int?,
      discNumber: data['disc_number'] as int?,
      releaseDate: data['release_date']?.toString(),
    );
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
  String? _highResCoverUrl(String? url) {
    if (url == null) return null;
    // Spotify CDN: upgrade 300 → 640 only
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildAppBar(context, colorScheme),
          PinnedButtonBar(
            onPlay: _tracks.isEmpty
                ? null
                : () => ref.read(playbackProvider.notifier).playTrackList(
                      _tracks,
                      shuffle: false,
                    ),
            onShuffle: _tracks.isEmpty ? null : _shufflePlayLocal,
          ),
          _buildInfoCard(context, colorScheme),
          _buildTrackList(context, colorScheme),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme colorScheme) {
    final imageUrl = _highResCoverUrl(widget.coverUrl) ?? widget.coverUrl;

    String? subtitle;
    if (_tracks.isNotEmpty) {
      subtitle = context.l10n.tracksCount(_tracks.length);
    }

    return StreamingHeader(
      title: widget.playlistName,
      subtitle: subtitle,
      imageUrl: imageUrl,
      expandedHeight: 380,
      fallbackIcon: Icons.playlist_play,
      actions: [
        if (_tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () => _confirmDownloadAll(context),
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

  Widget _buildTrackList(BuildContext context, ColorScheme colorScheme) {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            color: colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_tracks.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              context.l10n.errorNoTracksFound,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final track = _tracks[index];
        return KeyedSubtree(
          key: ValueKey(track.id),
          child: _PlaylistTrackItem(
            track: track,
            tracksList: _tracks,
            onDownload: () => _downloadTrack(context, track),
          ),
        );
      }, childCount: _tracks.length),
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

  void _shufflePlayLocal() {
    if (_tracks.isEmpty) return;
    final startIndex = Random().nextInt(_tracks.length);
    final messenger = ScaffoldMessenger.of(context);
    ref.read(playbackProvider.notifier).playTrackList(
          _tracks,
          startIndex: startIndex,
          shuffle: true,
        ).catchError((e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Cannot shuffle play tracks: $e')),
      );
    });
  }

  void _confirmDownloadAll(BuildContext context) {
    if (_tracks.isEmpty) return;
    showDialog(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          title: const Text('Download All'),
          content: Text('Download ${_tracks.length} tracks?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.dialogCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _downloadAll(context);
              },
              child: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  void _downloadAll(BuildContext context) {
    _downloadTracks(context, _tracks);
  }

  void _downloadTracks(BuildContext context, List<Track> tracks) {
    if (tracks.isEmpty) return;
    final settings = ref.read(settingsProvider);
    if (settings.askQualityBeforeDownload) {
      DownloadServicePicker.show(
        context,
        trackName: '${tracks.length} tracks',
        artistName: widget.playlistName,
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
}

/// Separate Consumer widget for each track - only rebuilds when this specific track's status changes
class _PlaylistTrackItem extends ConsumerWidget {
  final Track track;
  final List<Track> tracksList;
  final VoidCallback onDownload;

  const _PlaylistTrackItem({
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

    // Check local library for duplicate detection
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
          leading: track.coverUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: track.coverUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    memCacheWidth: 96,
                    cacheManager: CoverCacheManager.instance,
                  ),
                )
              : Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.music_note,
                    color: colorScheme.onSurfaceVariant,
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
                child: Text(
                  track.artistName,
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

      // Fallback
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

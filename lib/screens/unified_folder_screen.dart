import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path/path.dart' as p;
import 'package:hires_streamer/models/track.dart';
import 'package:hires_streamer/providers/playback_provider.dart';
import 'package:hires_streamer/screens/queue_tab.dart'; // To use UnifiedLibraryItem
import 'package:hires_streamer/providers/local_library_provider.dart';
import 'package:hires_streamer/providers/download_queue_provider.dart';
import 'package:hires_streamer/utils/app_bar_layout.dart';
import 'package:hires_streamer/providers/update_provider.dart';

class _FolderEntry {
  final String name;
  final String path;
  final bool isFolder;
  final UnifiedLibraryItem? track;
  final List<UnifiedLibraryItem> descendantTracks;

  _FolderEntry({
    required this.name,
    required this.path,
    required this.isFolder,
    this.track,
    required this.descendantTracks,
  });
}

class UnifiedFolderScreen extends ConsumerStatefulWidget {
  final String folderName;
  final String folderPath;

  const UnifiedFolderScreen({
    super.key,
    required this.folderName,
    required this.folderPath,
  });

  @override
  ConsumerState<UnifiedFolderScreen> createState() =>
      _UnifiedFolderScreenState();
}

class _UnifiedFolderScreenState extends ConsumerState<UnifiedFolderScreen> {
  final ScrollController _scrollController = ScrollController();
  late List<_FolderEntry> _entries;

  @override
  void initState() {
    super.initState();
  }

  void _calculateEntries(List<UnifiedLibraryItem> tracks) {
    final entriesMap = <String, _FolderEntry>{};
    final root = widget.folderPath;

    for (final item in tracks) {
      try {
        final relative = LocalLibraryNotifier.getRelativePath(
          item.filePath,
          root,
        );
        if (relative == null) continue;
        final parts = p.split(relative);

        if (parts.length == 1 && relative != '.') {
          // Direct track
          entriesMap[item.id] = _FolderEntry(
            name: item.trackName,
            path: item.filePath,
            isFolder: false,
            track: item,
            descendantTracks: [item],
          );
        } else if (parts.length > 1 || (parts.length == 1 && relative == '.')) {
          if (relative == '.') continue;

          // Subfolder
          final subfolderName = parts[0];
          if (subfolderName == 'document' ||
              subfolderName == 'primary' ||
              subfolderName == 'tree') {
            continue;
          }

          final subfolderPath = LocalLibraryNotifier.safJoin(
            root,
            subfolderName,
          );
          if (entriesMap.containsKey(subfolderPath)) {
            entriesMap[subfolderPath]!.descendantTracks.add(item);
          } else {
            entriesMap[subfolderPath] = _FolderEntry(
              name: subfolderName,
              path: subfolderPath,
              isFolder: true,
              descendantTracks: [item],
            );
          }
        }
      } catch (_) {
        // Ignore
      }
    }

    _entries = entriesMap.values.toList();
    // Sort: folders first, then tracks
    _entries.sort((a, b) {
      if (a.isFolder != b.isFolder) {
        return a.isFolder ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }


  Track _toTrack(UnifiedLibraryItem item) {
    // If it's a local item, we can get more metadata from localItem if present
    final local = item.localItem;
    return Track(
      id: item.id,
      name: item.trackName,
      artistName: item.artistName,
      albumName: item.albumName,
      albumArtist: local?.albumArtist,
      duration: local?.duration ?? 0,
      trackNumber: local?.trackNumber,
      discNumber: local?.discNumber,
      releaseDate: local?.releaseDate,
      coverUrl: item.localCoverPath ?? item.coverUrl,
      source: 'local',
      maxBitDepth: local?.bitDepth,
      maxSampleRate: local?.sampleRate?.toDouble(),
      format: local?.format,
      bitrate: local?.bitrate,
      fileSize: local?.fileSize,
    );
  }

  void _playAll(
    List<UnifiedLibraryItem> currentTracks, {
    bool shuffle = false,
  }) {
    // Collect all tracks recursively
    final tracksToPlay = currentTracks.map(_toTrack).toList();
    if (shuffle) {
      tracksToPlay.shuffle();
    } else {
      // Sort alphabetically by name
      tracksToPlay.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    final playbackService = ref.read(playbackProvider.notifier);
    playbackService.setShuffle(shuffle);
    playbackService.playTrackList(tracksToPlay);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Watch global state dynamically
    final localLibraryItems = ref.watch(
      localLibraryProvider.select((s) => s.items),
    );
    final historyItems = ref.watch(
      downloadHistoryProvider.select((s) => s.items),
    );

    // Merge and deduplicate
    final unifiedDownloaded = historyItems
        .map((item) => UnifiedLibraryItem.fromDownloadHistory(item))
        .toList(growable: false);
    final unifiedLocal = localLibraryItems
        .map((item) => UnifiedLibraryItem.fromLocalLibrary(item))
        .toList(growable: false);

    final Map<String, UnifiedLibraryItem> deduplicated = {};
    for (final item in unifiedDownloaded) {
      if (item.filePath.isNotEmpty) {
        deduplicated[LocalLibraryNotifier.normalizePath(item.filePath)] = item;
      }
    }
    for (final item in unifiedLocal) {
      if (item.filePath.isNotEmpty) {
        final key = LocalLibraryNotifier.normalizePath(item.filePath);
        if (!deduplicated.containsKey(key)) {
          deduplicated[key] = item;
        }
      }
    }

    // Filter by folderPath
    final currentTracks = deduplicated.values.where((item) {
      if (item.filePath.isEmpty) return false;
      return LocalLibraryNotifier.isPathInside(
        item.filePath,
        widget.folderPath,
      );
    }).toList();

    _calculateEntries(currentTracks);

    final updateState = ref.watch(updateProvider);
    final isDownloadingUpdate =
        updateState.isDownloading && updateState.updateInfo != null;
    final topPadding = normalizedHeaderTopPadding(context);
    final headerTopMargin = isDownloadingUpdate
        ? 0.0
        : MediaQuery.paddingOf(context).top + topPadding + 64.0;

    return Scaffold(
      body: Column(
        children: [
          // Stationary Header matching Home Page style
          Container(
            color: colorScheme.surface,
            padding: EdgeInsets.only(
              top: headerTopMargin,
              bottom: 16,
              left: 12,
              right: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.folderName,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: currentTracks.isEmpty
                              ? null
                              : () => _playAll(currentTracks, shuffle: false),
                          icon: const Icon(Icons.play_arrow, size: 20),
                          label: const Text('Play'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: currentTracks.isEmpty
                              ? null
                              : () => _playAll(currentTracks, shuffle: true),
                          icon: const Icon(Icons.shuffle, size: 20),
                          label: const Text('Shuffle'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                if (currentTracks.isEmpty)
                  const SliverFillRemaining(
                    child: Center(child: Text('No tracks found in this folder')),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 8, bottom: 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final entry = _entries[index];
                        if (entry.isFolder) {
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.folder,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            title: Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              '${entry.descendantTracks.length} tracks',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UnifiedFolderScreen(
                                    folderName: entry.name,
                                    folderPath: entry.path,
                                  ),
                                ),
                              );
                            },
                          );
                        }

                        final track = entry.track!;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 48,
                              height: 48,
                              color: colorScheme.surfaceContainerHighest,
                              child:
                                  track.localCoverPath != null &&
                                      track.localCoverPath!.isNotEmpty
                                  ? Image.file(
                                      File(track.localCoverPath!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Center(
                                            child: Icon(
                                              Icons.music_note,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                    )
                                  : (track.coverUrl != null &&
                                        track.coverUrl!.isNotEmpty)
                                  ? CachedNetworkImage(
                                      imageUrl: track.coverUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Center(
                                        child: Icon(
                                          Icons.music_note,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Icon(
                                        Icons.music_note,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                            ),
                          ),
                          title: Text(
                            track.trackName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            track.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                          onTap: () {
                            // Sort all tracks in this folder alphabetically
                            final allTracks = currentTracks.map(_toTrack).toList();
                            allTracks.sort(
                              (a, b) => a.name.toLowerCase().compareTo(
                                b.name.toLowerCase(),
                              ),
                            );

                            // Find index of clicked track
                            final startIndex = allTracks.indexWhere(
                              (t) => t.id == track.id,
                            );

                            ref
                                .read(playbackProvider.notifier)
                                .playTrackList(
                                  allTracks,
                                  startIndex: startIndex >= 0 ? startIndex : 0,
                                );
                          },
                          trailing: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              onPressed: () {
                                final allTracks =
                                    currentTracks.map(_toTrack).toList();
                                allTracks.sort(
                                  (a, b) => a.name.toLowerCase().compareTo(
                                    b.name.toLowerCase(),
                                  ),
                                );

                                final startIndex = allTracks.indexWhere(
                                  (t) => t.id == track.id,
                                );

                                ref.read(playbackProvider.notifier).playTrackList(
                                  allTracks,
                                  startIndex: startIndex >= 0 ? startIndex : 0,
                                );
                              },
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        );
                      }, childCount: _entries.length),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

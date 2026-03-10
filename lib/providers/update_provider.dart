import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hires_streamer/services/apk_downloader.dart';
import 'package:hires_streamer/services/notification_service.dart';
import 'package:hires_streamer/services/update_checker.dart';
import 'package:hires_streamer/utils/logger.dart';

final _log = AppLogger('UpdateProvider');

class UpdateState {
  final bool isDownloading;
  final double progress;
  final String statusText;
  final UpdateInfo? updateInfo;
  final String? error;

  const UpdateState({
    this.isDownloading = false,
    this.progress = 0,
    this.statusText = '',
    this.updateInfo,
    this.error,
  });

  UpdateState copyWith({
    bool? isDownloading,
    double? progress,
    String? statusText,
    UpdateInfo? updateInfo,
    String? error,
  }) {
    return UpdateState(
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      statusText: statusText ?? this.statusText,
      updateInfo: updateInfo ?? this.updateInfo,
      error: error ?? this.error,
    );
  }
}

class UpdateNotifier extends Notifier<UpdateState> {
  bool _isCancelled = false;

  @override
  UpdateState build() {
    return const UpdateState();
  }

  Future<void> downloadAndInstall(
    UpdateInfo updateInfo,
    String startingText,
  ) async {
    _isCancelled = false;
    final apkUrl = updateInfo.apkDownloadUrl;
    if (apkUrl == null) return;

    state = state.copyWith(
      isDownloading: true,
      progress: 0,
      statusText: startingText,
      updateInfo: updateInfo,
      error: null,
    );

    final notificationService = NotificationService();

    try {
      final filePath = await ApkDownloader.downloadApk(
        url: apkUrl,
        version: updateInfo.version,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          final receivedMB = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMB = (total / 1024 / 1024).toStringAsFixed(1);

          state = state.copyWith(
            progress: progress,
            statusText: '$receivedMB / $totalMB MB',
          );

          notificationService.showUpdateDownloadProgress(
            version: updateInfo.version,
            received: received,
            total: total,
          );
        },
      );

      if (filePath != null) {
        await notificationService.cancelUpdateNotification();
        await notificationService.showUpdateDownloadComplete(
          version: updateInfo.version,
        );

        state = state.copyWith(isDownloading: false, progress: 1.0);
        await ApkDownloader.installApk(filePath);
      } else {
        throw Exception('Download failed');
      }
    } catch (e) {
      if (_isCancelled) {
        state = const UpdateState();
        return;
      }
      _log.e('Update download error: $e');
      await notificationService.cancelUpdateNotification();
      await notificationService.showUpdateDownloadFailed();

      state = state.copyWith(
        isDownloading: false,
        error: e.toString(),
        statusText: 'Download failed',
      );
    }
  }

  void cancelDownload() {
    _isCancelled = true;
    ApkDownloader.cancelDownload();
    NotificationService().cancelUpdateNotification();
    state = const UpdateState();
  }

  void reset() {
    state = const UpdateState();
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);

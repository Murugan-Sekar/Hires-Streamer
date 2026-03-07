import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:hires_streamer/providers/extension_provider.dart';
import 'package:hires_streamer/providers/settings_provider.dart';
import 'package:hires_streamer/l10n/l10n.dart';
import 'package:hires_streamer/services/platform_bridge.dart';
import 'package:hires_streamer/utils/file_access.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // State variables
  bool _storagePermissionGranted = false;
  bool _notificationPermissionGranted = false;
  String? _selectedDirectory;
  String? _selectedTreeUri;
  bool _isLoading = false;
  int _androidSdkVersion = 0;

  // Mode selection
  String _selectedMode = 'downloader';

  // We add 1 for the Welcome step
  int get _totalSteps => (_androidSdkVersion >= 33 ? 4 : 3) + 1;

  @override
  void initState() {
    super.initState();
    _initDeviceInfo();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initDeviceInfo() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (!mounted) return;
      setState(() {
        _androidSdkVersion = androidInfo.version.sdkInt;
      });
    }
    if (!mounted) return;
    await _checkInitialPermissions();
  }

  Future<void> _checkInitialPermissions() async {
    if (Platform.isIOS) {
      final notificationStatus = await Permission.notification.status;
      if (mounted) {
        setState(() {
          _storagePermissionGranted = true;
          _notificationPermissionGranted =
              notificationStatus.isGranted || notificationStatus.isProvisional;
        });
      }
    } else if (Platform.isAndroid) {
      bool storageGranted = false;

      if (_androidSdkVersion >= 33) {
        final audioStatus = await Permission.audio.status;
        storageGranted = audioStatus.isGranted;
      } else if (_androidSdkVersion >= 30) {
        final manageStatus = await Permission.manageExternalStorage.status;
        storageGranted = manageStatus.isGranted;
      } else {
        final storageStatus = await Permission.storage.status;
        storageGranted = storageStatus.isGranted;
      }

      PermissionStatus notificationStatus = PermissionStatus.granted;
      if (_androidSdkVersion >= 33) {
        notificationStatus = await Permission.notification.status;
      }

      if (mounted) {
        setState(() {
          _storagePermissionGranted = storageGranted;
          _notificationPermissionGranted = notificationStatus.isGranted;
        });
      }
    }
  }

  Future<void> _requestStoragePermission() async {
    setState(() => _isLoading = true);
    try {
      if (Platform.isIOS) {
        setState(() => _storagePermissionGranted = true);
      } else if (Platform.isAndroid) {
        bool allGranted = false;

        if (_androidSdkVersion >= 33) {
          var audioStatus = await Permission.audio.status;
          if (!audioStatus.isGranted) {
            audioStatus = await Permission.audio.request();
          }
          allGranted = audioStatus.isGranted;

          if (audioStatus.isPermanentlyDenied) {
            await _showPermissionDeniedDialog('Audio');
            return;
          }
        } else if (_androidSdkVersion >= 30) {
          var manageStatus = await Permission.manageExternalStorage.status;
          if (!manageStatus.isGranted) {
            final shouldOpen = await _showAndroid11StorageDialog();
            if (shouldOpen == true) {
              await Permission.manageExternalStorage.request();
              await Future.delayed(const Duration(milliseconds: 500));
              manageStatus = await Permission.manageExternalStorage.status;
            }
          }
          allGranted = manageStatus.isGranted;
        } else {
          final status = await Permission.storage.request();
          allGranted = status.isGranted;
          if (status.isPermanentlyDenied) {
            await _showPermissionDeniedDialog('Storage');
            return;
          }
        }

        setState(() => _storagePermissionGranted = allGranted);
        if (!allGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.setupPermissionDeniedMessage)),
          );
        }
      }
    } catch (e) {
      debugPrint('Permission error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<bool?> _showAndroid11StorageDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.setupStorageAccessRequired),
        content: Text(
          '${context.l10n.setupStorageAccessMessageAndroid11}\n\n'
          '${context.l10n.setupAllowAccessToManageFiles}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.setupOpenSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _requestNotificationPermission() async {
    setState(() => _isLoading = true);
    try {
      if (Platform.isIOS) {
        final status = await Permission.notification.request();
        if (status.isGranted || status.isProvisional) {
          setState(() => _notificationPermissionGranted = true);
        } else if (status.isPermanentlyDenied) {
          await _showPermissionDeniedDialog('Notification');
        }
      } else if (_androidSdkVersion >= 33) {
        final status = await Permission.notification.request();
        if (status.isGranted) {
          setState(() => _notificationPermissionGranted = true);
        } else if (status.isPermanentlyDenied) {
          await _showPermissionDeniedDialog('Notification');
        }
      } else {
        setState(() => _notificationPermissionGranted = true);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showPermissionDeniedDialog(String permissionType) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.setupPermissionRequired(permissionType)),
        content: Text(
          context.l10n.setupPermissionRequiredMessage(permissionType),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.dialogCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text(context.l10n.setupOpenSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDirectory() async {
    setState(() => _isLoading = true);
    try {
      if (Platform.isIOS) {
        await _showIOSDirectoryOptions();
      } else {
        final result = await PlatformBridge.pickSafTree();
        if (result != null) {
          final treeUri = result['tree_uri'] as String? ?? '';
          final displayName = result['display_name'] as String? ?? '';
          if (treeUri.isNotEmpty) {
            setState(() {
              _selectedTreeUri = treeUri;
              _selectedDirectory = displayName.isNotEmpty
                  ? displayName
                  : treeUri;
            });
          }
        }

        // Android fallback if user cancelled SAF picker
        if (_selectedTreeUri == null || _selectedTreeUri!.isEmpty) {
          final defaultDir = await _getDefaultDirectory();
          if (mounted) {
            final useDefault = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(context.l10n.setupUseDefaultFolder),
                content: Text(
                  '${context.l10n.setupNoFolderSelected}\n\n$defaultDir',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(context.l10n.dialogCancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(context.l10n.setupUseDefault),
                  ),
                ],
              ),
            );
            if (useDefault == true) {
              setState(() {
                _selectedTreeUri = '';
                _selectedDirectory = defaultDir;
              });
            }
          }
        }
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showIOSDirectoryOptions() async {
    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                context.l10n.setupDownloadLocationTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                context.l10n.setupDownloadLocationIosMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.folder_special, color: colorScheme.primary),
              title: Text(context.l10n.setupAppDocumentsFolder),
              onTap: () async {
                final dir = await _getDefaultDirectory();
                setState(() => _selectedDirectory = dir);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.cloud, color: colorScheme.onSurfaceVariant),
              title: Text(context.l10n.setupChooseFromFiles),
              onTap: () async {
                Navigator.pop(ctx);
                final result = await FilePicker.platform.getDirectoryPath();
                if (result != null) {
                  // iOS: Validate the selected path is writable
                  if (Platform.isIOS) {
                    final validation = validateIosPath(result);
                    if (!validation.isValid) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              validation.errorReason ??
                                  'Invalid folder selected',
                            ),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                      return;
                    }
                  }
                  setState(() => _selectedDirectory = result);
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<String> _getDefaultDirectory() async {
    if (Platform.isAndroid) {
      final musicDir = Directory('/storage/emulated/0/Music/SpotiFLAC');
      try {
        if (!await musicDir.exists()) {
          await musicDir.create(recursive: true);
        }
        return musicDir.path;
      } catch (e) {
        debugPrint('Cannot create Music folder: $e');
      }
    }
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/SpotiFLAC';
  }

  Future<void> _completeSetup() async {
    if (_selectedDirectory == null) return;
    setState(() => _isLoading = true);

    try {
      if (!Platform.isAndroid ||
          _selectedTreeUri == null ||
          _selectedTreeUri!.isEmpty) {
        final dir = Directory(_selectedDirectory!);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        ref.read(settingsProvider.notifier).setStorageMode('app');
        ref
            .read(settingsProvider.notifier)
            .setDownloadDirectory(_selectedDirectory!);
        ref.read(settingsProvider.notifier).setDownloadTreeUri('');
      } else {
        ref.read(settingsProvider.notifier).setStorageMode('saf');
        ref
            .read(settingsProvider.notifier)
            .setDownloadTreeUri(
              _selectedTreeUri!,
              displayName: _selectedDirectory,
            );
      }

      ref.read(settingsProvider.notifier).setMetadataSource('deezer');
      await ref
          .read(extensionProvider.notifier)
          .ensureSpotifyWebExtensionReady();
      ref.read(settingsProvider.notifier).setFirstLaunchComplete();

      if (mounted) context.go('/tutorial');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _nextPage() {
    bool canProceed = false;
    // Step 0 is Welcome, always can proceed
    if (_currentStep == 0) {
      canProceed = true;
    } else {
      // Logic for other steps (offset by 1 because of welcome step)
      // Step 1: Storage
      // Step 2: Notification (if android 13+) OR Directory
      // etc.
      canProceed = _isStepCompleted(_currentStep);
    }

    if (canProceed) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    }
  }

  void _prevPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep--);
  }

  bool _isStepCompleted(int step) {
    if (step == 0) return true; // Welcome

    // Adjust step index for logic because we added Welcome at 0
    final logicStep = step - 1;

    if (_androidSdkVersion >= 33) {
      switch (logicStep) {
        case 0:
          return _storagePermissionGranted;
        case 1:
          return _notificationPermissionGranted;
        case 2:
          return _selectedDirectory != null;
        case 3:
          return true; // Mode selection always has a default
      }
    } else {
      switch (logicStep) {
        case 0:
          return _storagePermissionGranted;
        case 1:
          return _selectedDirectory != null;
        case 2:
          return true; // Mode selection always has a default
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Calculate progress
    final progress = (_currentStep + 1) / _totalSteps;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // Content
          Positioned.fill(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildWelcomeStep(colorScheme),
                _buildStorageStep(colorScheme),
                if (_androidSdkVersion >= 33)
                  _buildNotificationStep(colorScheme),
                _buildDirectoryStep(colorScheme),
                _buildModeSelectionStep(colorScheme),
              ],
            ),
          ),

          // Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      IconButton.filledTonal(
                        onPressed: _prevPage,
                        icon: const Icon(Icons.arrow_back),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          foregroundColor: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      const SizedBox(width: 48), // Spacer
                    const Spacer(),
                    // Progress Indicator
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 4,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            color: colorScheme.primary,
                            strokeCap: StrokeCap.round,
                          ),
                          Center(
                            child: Text(
                              '${_currentStep + 1}/$_totalSteps',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: const _CustomFABLocation(
        FloatingActionButtonLocation.endFloat,
        offsetY: -16, // Move button up slightly
      ),
      floatingActionButton: _currentStep < _totalSteps - 1
          ? FloatingActionButton.extended(
              onPressed: _isStepCompleted(_currentStep) ? _nextPage : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              label: Row(
                children: [
                  Text(
                    context.l10n.setupNext,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward),
                ],
              ),
              icon: const SizedBox.shrink(), // Custom layout
            )
          : FilledButton.tonalIcon(
              onPressed: _isLoading ? null : _completeSetup,
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(context.l10n.setupGetStarted),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
    );
  }

  Widget _buildWelcomeStep(ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1.0).clamp(1.0, 1.4);
        final logoSize = (shortestSide * 0.28).clamp(90.0, 120.0);
        final titleGap = (shortestSide * 0.03).clamp(8.0, 16.0);
        final subtitleGap = (shortestSide * 0.015).clamp(4.0, 8.0);
        final minContentHeight = constraints.maxHeight;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minContentHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 190, // Reduced from 220 for more compact view
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/logo-transparant.png',
                        width: logoSize,
                        height: logoSize,
                        color: colorScheme.primary,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: titleGap),
                      Text(
                        // context.l10n.appName,
                        "Hi-Res Streamer",
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                              fontSize:
                                  (Theme.of(
                                        context,
                                      ).textTheme.displaySmall?.fontSize ??
                                      36) *
                                  (1 + ((textScale - 1) * 0.18)),
                            ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: subtitleGap),
                Text(
                  context.l10n.setupDownloadInFlac,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 100), // Action area placeholder
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStorageStep(ColorScheme colorScheme) {
    return _StepLayout(
      title: context.l10n.setupStorageRequired,
      description: context.l10n.setupStorageDescription,
      icon: Icons.folder,
      child: _storagePermissionGranted
          ? _SuccessCard(
              text: context.l10n.setupStorageGranted,
              colorScheme: colorScheme,
            )
          : FilledButton.tonalIcon(
              onPressed: _requestStoragePermission,
              icon: const Icon(Icons.folder_open),
              label: Text(context.l10n.setupGrantPermission),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
    );
  }

  Widget _buildNotificationStep(ColorScheme colorScheme) {
    return _StepLayout(
      title: context.l10n.setupNotificationEnable,
      description: context.l10n.setupNotificationBackgroundDescription,
      icon: Icons.notifications,
      child: _notificationPermissionGranted
          ? _SuccessCard(
              text: context.l10n.setupNotificationGranted,
              colorScheme: colorScheme,
            )
          : Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _requestNotificationPermission,
                  icon: const Icon(Icons.notifications_active),
                  label: Text(context.l10n.setupEnableNotifications),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _notificationPermissionGranted = true),
                  child: Text(context.l10n.setupSkipForNow),
                ),
              ],
            ),
    );
  }

  Widget _buildDirectoryStep(ColorScheme colorScheme) {
    return _StepLayout(
      title: context.l10n.setupFolderChoose,
      description: context.l10n.setupFolderDescription,
      icon: Icons.create_new_folder,
      child: Column(
        children: [
          if (_selectedDirectory != null)
            FilledButton.tonalIcon(
              onPressed: _selectDirectory,
              icon: const Icon(Icons.folder),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _selectedDirectory!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, size: 18),
                ],
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          else
            FilledButton.tonalIcon(
              onPressed: _selectDirectory,
              icon: const Icon(Icons.create_new_folder),
              label: Text(context.l10n.setupSelectFolder),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeSelectionStep(ColorScheme colorScheme) {
    return _StepLayout(
      title: context.l10n.setupModeSelectionTitle,
      description: context.l10n.setupModeSelectionDescription,
      icon: Icons.tune,
      child: Column(
        children: [
          _ModeCard(
            icon: Icons.download,
            title: context.l10n.setupModeDownloaderTitle,
            features: [
              context.l10n.setupModeDownloaderFeature1,
              context.l10n.setupModeDownloaderFeature2,
              context.l10n.setupModeDownloaderFeature3,
            ],
            isSelected: _selectedMode == 'downloader',
            onTap: () => setState(() => _selectedMode = 'downloader'),
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.setupModeChangeableLater,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StepLayout extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Widget child;

  const _StepLayout({
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final iconPadding = (shortestSide * 0.04).clamp(10.0, 14.0);
        final iconSize = (shortestSide * 0.26).clamp(85.0, 115.0);
        final titleGap = (shortestSide * 0.03).clamp(8.0, 16.0);
        final descriptionGap = (shortestSide * 0.015).clamp(4.0, 8.0);
        final actionGap = (shortestSide * 0.04).clamp(12.0, 24.0);
        final minContentHeight = constraints.maxHeight;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minContentHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 190, // Consistent with welcome step
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.all(iconPadding),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: iconSize,
                          color: colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: titleGap),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: descriptionGap),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: actionGap),
                // Action area with min height to stabilize header
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 100),
                  child: Center(child: child),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final String text;
  final ColorScheme colorScheme;

  const _SuccessCard({required this.text, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // Compact card
        children: [
          Icon(
            Icons.check_circle,
            size: 20,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Flexible(
            // Allow text to wrap if screen is very narrow
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> features;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.features,
    required this.isSelected,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 22,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 22,
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurface,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...features.map(
                    (feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '\u2022 ',
                            style: TextStyle(
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              feature,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: isSelected
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                            ),
                          ),
                        ],
                      ),
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
}

class _CustomFABLocation extends FloatingActionButtonLocation {
  final FloatingActionButtonLocation location;
  final double offsetY;

  const _CustomFABLocation(this.location, {this.offsetY = 0});

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    Offset offset = location.getOffset(scaffoldGeometry);
    return Offset(offset.dx, offset.dy + offsetY);
  }
}

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_links.dart';
import '../../app/app_controller.dart';
import '../../data/app_update_installer.dart';
import '../../core/localization/app_strings.dart';
import '../../data/app_update_service.dart';
import '../../data/calendar_import_service.dart';
import '../../data/cloud_sync_service.dart';
import '../../data/flight_spreadsheet_import_service.dart';
import '../../data/flight_repository.dart';
import '../../data/airport_localization.dart';
import '../../domain/flight.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.controller,
    this.isActive = false,
  });
  final AppController controller;
  final bool isActive;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  AppController get controller => widget.controller;

  bool _isRecognizingSpreadsheet = false;
  bool _isReadingCalendar = false;
  bool _isCheckingForUpdates = false;
  bool _hasCheckedForUpdatesAutomatically = false;
  bool _hasScheduledAutomaticUpdateCheck = false;
  String? _promptedUpdateVersion;
  AppUpdateResult? _updateResult;
  final AppUpdateService _updateService = AppUpdateService();

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _scheduleAutomaticUpdateCheck();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _scheduleAutomaticUpdateCheck();
    }
  }

  void _scheduleAutomaticUpdateCheck() {
    if (_hasCheckedForUpdatesAutomatically ||
        _hasScheduledAutomaticUpdateCheck) {
      return;
    }
    _hasScheduledAutomaticUpdateCheck = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) {
        _hasScheduledAutomaticUpdateCheck = false;
        return;
      }
      _hasCheckedForUpdatesAutomatically = true;
      unawaited(_checkForUpdates(context, automatic: true));
    });
  }

  @override
  void dispose() {
    _updateService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          if (_isRecognizingSpreadsheet)
            const SliverToBoxAdapter(child: _SpreadsheetRecognizingNotice()),
          if (_isReadingCalendar)
            const SliverToBoxAdapter(child: _CalendarReadingNotice()),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.bottomBarClearance(context),
            ),
            sliver: SliverList.list(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  decoration: ShapeDecoration(
                    color: const Color(0xFFB9A9F2),
                    shape: AppShapes.large,
                    shadows: _cardShadow(),
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Colors.black),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .09),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.phone_android_rounded,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.t('localData'),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s.t('localOnly'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${controller.flights.length}',
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ProfileActionTile(
                            title: s.t('exportBackup'),
                            subtitle: 'JSON',
                            icon: Icons.ios_share_rounded,
                            color: Colors.black,
                            backgroundColor: const Color(0xFFB9A9F2),
                            textColor: Colors.black,
                            secondaryTextColor: const Color(0xA6252A2E),
                            onTap: () => _export(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ProfileActionTile(
                            title: s.t('importWebData'),
                            subtitle: 'JSON',
                            icon: Icons.file_download_outlined,
                            color: Colors.black,
                            backgroundColor: const Color(0xFF9CCFE6),
                            textColor: Colors.black,
                            secondaryTextColor: const Color(0xA6252A2E),
                            onTap: () => _import(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ProfileActionTile(
                            title: s.t('importExcel'),
                            subtitle: '.xlsx / .xls / .csv',
                            icon: Icons.table_view_rounded,
                            color: Colors.black,
                            backgroundColor: const Color(0xFFA8D7AF),
                            textColor: Colors.black,
                            secondaryTextColor: const Color(0xA6252A2E),
                            onTap: () => _importSpreadsheet(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ProfileActionTile(
                            title: s.t('importCalendar'),
                            subtitle: '系统日历',
                            icon: Icons.calendar_month_rounded,
                            color: Colors.black,
                            backgroundColor: const Color(0xFFE2B4D1),
                            textColor: Colors.black,
                            secondaryTextColor: const Color(0xA6252A2E),
                            onTap: () => _importCalendar(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListenableBuilder(
                      listenable: controller.cloudSync,
                      builder: (context, _) {
                        final cloud = controller.cloudSync.state;
                        final value = switch (cloud.status) {
                          CloudSyncStatus.syncing => s.t('cloudSyncing'),
                          CloudSyncStatus.synced => s.t('cloudSynced'),
                          CloudSyncStatus.error => s.t('cloudSyncFailed'),
                          CloudSyncStatus.ready => s.t('cloudReady'),
                          CloudSyncStatus.disconnected => s.t('notConfigured'),
                        };
                        final isConfigured = cloud.isConfigured;
                        return _ProfileActionTile(
                          title: s.t('cloudSync'),
                          value: value,
                          icon: isConfigured
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_outlined,
                          color: isConfigured
                              ? Colors.black
                              : AppColors.textTertiary,
                          backgroundColor: isConfigured
                              ? AppColors.lime
                              : AppColors.surfaceElevated,
                          textColor: isConfigured
                              ? Colors.black
                              : AppColors.textPrimary,
                          secondaryTextColor: isConfigured
                              ? const Color(0xA6000000)
                              : AppColors.textSecondary,
                          wide: true,
                          onTap: () => _openCloudSync(context),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.section),
                Text(s.t('settings'), style: AppTextStyles.sectionTitle),
                const SizedBox(height: 12),
                Column(
                  children: [
                    _ProfileActionTile(
                      title: s.t('travellerName'),
                      value: controller.travellerName == 'TRAVELER'
                          ? s.t('travellerNameEmpty')
                          : controller.travellerName,
                      icon: Icons.badge_outlined,
                      color: Colors.black,
                      backgroundColor: const Color(0xFFA8D7AF),
                      textColor: Colors.black,
                      secondaryTextColor: Colors.black,
                      wide: true,
                      onTap: () => _editTravellerName(context),
                    ),
                    const SizedBox(height: 10),
                    _ProfileActionTile(
                      title: s.t('language'),
                      value: controller.locale.languageCode == 'zh'
                          ? s.t('chinese')
                          : s.t('english'),
                      icon: Icons.translate_rounded,
                      color: Colors.black,
                      backgroundColor: const Color(0xFF9CCFE6),
                      textColor: Colors.black,
                      secondaryTextColor: Colors.black,
                      wide: true,
                      onTap: () => _language(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.section),
                Text(s.t('about'), style: AppTextStyles.sectionTitle),
                const SizedBox(height: 12),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  color: AppColors.surfaceElevated,
                  borderRadius: AppRadii.large,
                  showBorder: false,
                  boxShadow: _cardShadow(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.lime.withValues(alpha: .14),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.flight_takeoff_rounded,
                                color: AppColors.lime,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Flight Footprint',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    s.t('version'),
                                    style: AppTextStyles.label.copyWith(
                                      color: AppColors.purple,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          0,
                          AppSpacing.md,
                          AppSpacing.md,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _ProfileAboutButton(
                                title: s.t('checkForUpdates'),
                                value: _updateValue(),
                                icon: Icons.system_update_alt_rounded,
                                backgroundColor: const Color(0xFFA8D7AF),
                                foregroundColor: Colors.black,
                                onPressed: () => _checkForUpdates(context),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ProfileAboutButton(
                                title: s.t('githubProject'),
                                icon: Icons.code_rounded,
                                backgroundColor: const Color(0xFFB9A9F2),
                                foregroundColor: Colors.black,
                                onPressed: AppLinks.githubRepository == null
                                    ? null
                                    : () => _openExternalUrl(
                                        context,
                                        AppLinks.githubRepository!,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.lg,
                        ),
                        child: Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 2,
                            children: [
                              const Icon(
                                Icons.shield_outlined,
                                color: AppColors.textTertiary,
                                size: 18,
                              ),
                              Text(
                                s.t('privacy'),
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySecondary.copyWith(
                                  color: AppColors.textTertiary,
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
        ],
      ),
    );
  }

  List<BoxShadow> _cardShadow() => [
    BoxShadow(
      color: Colors.black.withValues(alpha: .22),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];

  String _updateSubtitle(BuildContext context) {
    final strings = context.strings;
    if (_isCheckingForUpdates) return strings.t('checkingForUpdates');
    final result = _updateResult;
    if (result?.status == UpdateCheckStatus.available) {
      return '${strings.t('updateAvailable')} · v${result!.latestVersion}';
    }
    if (result?.status == UpdateCheckStatus.upToDate) {
      return strings.t('upToDate');
    }
    if (result?.status == UpdateCheckStatus.unavailable) {
      return strings.t('updateCheckFailed');
    }
    return strings.t('checkForUpdatesHint');
  }

  String? _updateValue() {
    if (_isCheckingForUpdates) return '…';
    final result = _updateResult;
    if (result?.status == UpdateCheckStatus.available) {
      return 'v${result!.latestVersion}';
    }
    return null;
  }

  Future<void> _checkForUpdates(
    BuildContext context, {
    bool automatic = false,
  }) async {
    if (_isCheckingForUpdates) return;
    final strings = context.strings;
    setState(() {
      _isCheckingForUpdates = true;
    });
    final result = await _updateService.checkForUpdates();
    if (!context.mounted) return;
    setState(() {
      _isCheckingForUpdates = false;
      _updateResult = result;
    });

    if (automatic) {
      // The page remains mounted inside the shell's IndexedStack even after
      // the user switches tabs. Do not place a dialog over another page; let
      // the next visit retry the quiet check instead.
      if (!widget.isActive) {
        _hasCheckedForUpdatesAutomatically = false;
        return;
      }
      if (result.status == UpdateCheckStatus.available) {
        await _showUpdatePrompt(context, result);
      }
      return;
    }

    switch (result.status) {
      case UpdateCheckStatus.available:
        await _showUpdatePrompt(context, result);
      case UpdateCheckStatus.upToDate:
        _message(context, strings.t('upToDate'));
      case UpdateCheckStatus.notConfigured:
        _message(context, strings.t('githubProjectNotConfigured'));
      case UpdateCheckStatus.unavailable:
        _message(context, strings.t('updateCheckFailed'));
    }
  }

  Future<void> _showUpdatePrompt(
    BuildContext context,
    AppUpdateResult result,
  ) async {
    final latestVersion = result.latestVersion;
    if (latestVersion == null || _promptedUpdateVersion == latestVersion) {
      return;
    }
    _promptedUpdateVersion = latestVersion;

    final strings = context.strings;
    final currentVersion = result.currentVersion ?? '—';
    final canInstallInApp =
        result.canDownloadInApp && AppUpdateInstaller.isSupported;
    final shouldOpen = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: AppShapes.large,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.lime.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update_alt_rounded,
                  color: AppColors.lime,
                  size: 26,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                strings.t('updateAvailable'),
                style: AppTextStyles.sectionTitle,
              ),
              const SizedBox(height: 8),
              Text(
                '${strings.t('currentVersionLabel')}  v$currentVersion',
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: 4),
              Text(
                '${strings.t('latestVersionLabel')}  v$latestVersion',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.lime,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(strings.t('updateLater')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.lime,
                      foregroundColor: Colors.black,
                      shape: AppShapes.pill,
                    ),
                    icon: Icon(
                      canInstallInApp
                          ? Icons.download_rounded
                          : Icons.open_in_new_rounded,
                      size: 18,
                    ),
                    label: Text(
                      canInstallInApp
                          ? strings.t('updateNow')
                          : strings.t('openRelease'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldOpen != true || !context.mounted) return;
    if (canInstallInApp) {
      await _downloadAndInstallUpdate(context, result);
    } else if (result.releaseUrl != null) {
      await _openExternalUrl(context, result.releaseUrl!);
    }
  }

  Future<void> _downloadAndInstallUpdate(
    BuildContext context,
    AppUpdateResult result,
  ) async {
    final strings = context.strings;
    final progress = ValueNotifier<double?>(0);
    var dialogVisible = true;
    var apkDownloaded = false;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.background.withValues(alpha: .86),
      builder: (_) => _UpdateDownloadDialog(progress: progress),
    );

    try {
      // Give the progress surface one frame to appear before network I/O.
      await WidgetsBinding.instance.endOfFrame;
      final apk = await _updateService.downloadApk(
        result,
        onProgress: (received, total) {
          progress.value = total == null || total <= 0
              ? null
              : (received / total).clamp(0.0, 1.0).toDouble();
        },
      );
      apkDownloaded = true;
      if (context.mounted && dialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogVisible = false;
      }
      if (context.mounted) await dialogFuture;
      if (!context.mounted) return;
      await AppUpdateInstaller.install(apk);
    } catch (error) {
      if (context.mounted && dialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogVisible = false;
        await dialogFuture;
      }
      if (context.mounted) {
        final message = apkDownloaded
            ? strings.t('installUpdateFailed')
            : strings.t('downloadUpdateFailed');
        _message(context, '$message: $error');
      }
    } finally {
      progress.dispose();
    }
  }

  Future<void> _openExternalUrl(BuildContext context, Uri uri) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _message(context, context.strings.t('githubOpenFailed'));
      }
    } catch (_) {
      if (context.mounted) {
        _message(context, context.strings.t('githubOpenFailed'));
      }
    }
  }

  Future<void> _export(BuildContext context) async {
    try {
      final source = await controller.repository.exportBackup();
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/flight-footprint-backup.json');
      await file.writeAsString(source, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          title: 'Flight Footprint Backup',
        ),
      );
      if (context.mounted) {
        _message(context, context.strings.t('backupSuccess'));
      }
    } catch (error) {
      if (context.mounted) {
        _message(context, '${context.strings.t('operationFailed')}: $error');
      }
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      final pickerResult = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = pickerResult?.path;
      if (path == null) return;
      final result = await controller.data.importBackup(
        await File(path).readAsString(),
      );
      if (context.mounted) {
        final message = context.strings.isZh
            ? '导入完成：${result.flightsMerged} 条航班，${result.placesMerged} 个城市'
            : 'Imported: ${result.flightsMerged} flights, ${result.placesMerged} places';
        _message(context, message);
      }
    } catch (error) {
      if (context.mounted) {
        _message(context, '${context.strings.t('operationFailed')}: $error');
      }
    }
  }

  Future<void> _importSpreadsheet(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!context.mounted) return;
      final noticeStartedAt = DateTime.now();
      setState(() => _isRecognizingSpreadsheet = true);
      late SpreadsheetImportResult parsed;
      late FlightImportPreview preview;
      try {
        // Let the page-level notice paint before the background parser starts.
        await WidgetsBinding.instance.endOfFrame;
        parsed = await controller.parseFlightSpreadsheet(
          bytes: bytes,
          fileName: picked.name,
        );
        if (parsed.hasRows) {
          preview = await controller.previewSpreadsheetDetails(
            parsed.rows.map((row) => row.flight),
          );
        }
      } finally {
        const minimumNoticeDuration = Duration(milliseconds: 900);
        final elapsed = DateTime.now().difference(noticeStartedAt);
        final remaining = minimumNoticeDuration - elapsed;
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
        if (mounted) setState(() => _isRecognizingSpreadsheet = false);
      }
      if (!context.mounted) return;
      if (!parsed.hasRows) {
        _message(context, context.strings.t('spreadsheetNoRows'));
        return;
      }
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            _SpreadsheetPreviewSheet(result: parsed, preview: preview),
      );
      if (confirmed != true || !context.mounted) return;
      var overwriteExisting = false;
      if (preview.summary.conflicts > 0) {
        final decision = await _confirmSpreadsheetOverwrite(
          context,
          preview.summary.conflicts,
        );
        if (decision == null || !context.mounted) return;
        overwriteExisting = decision;
      }

      final progress = ValueNotifier<double?>(0);
      final progressDialog = showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: AppColors.background,
        builder: (_) => _SpreadsheetProgressDialog(progress: progress),
      );
      FlightImportSummary imported;
      try {
        imported = await controller.importSpreadsheetFlights(
          parsed.rows.map((row) => row.flight),
          overwriteExisting: overwriteExisting,
          onProgress: (completed, total) {
            progress.value = total == 0 ? 1 : completed / total;
          },
        );
      } finally {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        progress.dispose();
        await progressDialog;
      }
      if (!context.mounted) return;
      await _showSpreadsheetComplete(context, imported);
    } catch (error) {
      if (context.mounted) {
        _message(context, '${context.strings.t('operationFailed')}: $error');
      }
    }
  }

  Future<void> _importCalendar(BuildContext context) async {
    if (_isReadingCalendar) return;
    final startedAt = DateTime.now();
    setState(() => _isReadingCalendar = true);
    CalendarImportResult scanned;
    try {
      // Give the page-level notice one frame to paint before the Android
      // permission prompt or calendar provider query begins.
      await WidgetsBinding.instance.endOfFrame;
      scanned = await controller.scanCalendarFlights();
    } finally {
      const minimumNoticeDuration = Duration(milliseconds: 500);
      final elapsed = DateTime.now().difference(startedAt);
      final remaining = minimumNoticeDuration - elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (mounted) setState(() => _isReadingCalendar = false);
    }

    if (!context.mounted) return;
    switch (scanned.status) {
      case CalendarScanStatus.permissionDenied:
        _message(context, context.strings.t('calendarPermissionDenied'));
        return;
      case CalendarScanStatus.unsupported:
        _message(context, context.strings.t('calendarUnsupported'));
        return;
      case CalendarScanStatus.failed:
        _message(
          context,
          '${context.strings.t('operationFailed')}: ${scanned.errorCode ?? 'calendar'}',
        );
        return;
      case CalendarScanStatus.available:
        break;
    }
    if (scanned.flights.isEmpty) {
      _message(context, context.strings.t('calendarNoFlights'));
      return;
    }

    final selected = await showModalBottomSheet<List<CalendarFlightDraft>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CalendarPreviewSheet(result: scanned),
    );
    if (selected == null || !context.mounted) return;
    if (selected.isEmpty) {
      _message(context, context.strings.t('calendarNoSelection'));
      return;
    }

    final preview = await controller.previewCalendarFlights(selected);
    if (!context.mounted) return;
    var overwriteExisting = false;
    if (preview.summary.conflicts > 0) {
      final decision = await _confirmSpreadsheetOverwrite(
        context,
        preview.summary.conflicts,
      );
      if (decision == null || !context.mounted) return;
      overwriteExisting = decision;
    }

    FlightImportSummary imported;
    try {
      imported = await controller.importCalendarFlights(
        selected,
        overwriteExisting: overwriteExisting,
      );
    } catch (error) {
      if (context.mounted) {
        _message(context, '${context.strings.t('operationFailed')}: $error');
      }
      return;
    }
    if (!context.mounted) return;
    await _showCalendarComplete(context, imported);
  }

  Future<void> _showCalendarComplete(
    BuildContext context,
    FlightImportSummary summary,
  ) async {
    final s = context.strings;
    final detail = s
        .t('calendarImportDoneDetail')
        .replaceFirst('{added}', '${summary.added}')
        .replaceFirst('{updated}', '${summary.updated}')
        .replaceFirst('{unchanged}', '${summary.unchanged}')
        .replaceFirst('{skipped}', '${summary.skipped}');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.event_available_rounded, color: AppColors.lime),
        title: Text(s.t('calendarImportDone')),
        content: Text(detail),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.t('close')),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmSpreadsheetOverwrite(
    BuildContext context,
    int conflictCount,
  ) => showDialog<bool?>(
    context: context,
    builder: (dialogContext) {
      final s = context.strings;
      final message = s
          .t('spreadsheetOverwriteMessage')
          .replaceFirst('{count}', '$conflictCount');
      return AlertDialog(
        title: Text(s.t('spreadsheetOverwriteTitle')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.t('cancel')),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.t('spreadsheetKeepExisting')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.t('spreadsheetOverwrite')),
          ),
        ],
      );
    },
  );

  Future<void> _showSpreadsheetComplete(
    BuildContext context,
    FlightImportSummary summary,
  ) async {
    final s = context.strings;
    final detail = s
        .t('spreadsheetImportDoneDetail')
        .replaceFirst('{added}', '${summary.added}')
        .replaceFirst('{updated}', '${summary.updated}')
        .replaceFirst('{unchanged}', '${summary.unchanged}')
        .replaceFirst('{skipped}', '${summary.skipped}');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: AppColors.lime),
        title: Text(s.t('spreadsheetImportDone')),
        content: Text(detail),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.t('close')),
          ),
        ],
      ),
    );
  }

  void _language(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(context.strings.t('chinese')),
                trailing: controller.locale.languageCode == 'zh'
                    ? const Icon(Icons.check_circle, color: AppColors.lime)
                    : null,
                onTap: () async {
                  await controller.setLocale(const Locale('zh'));
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(context.strings.t('english')),
                trailing: controller.locale.languageCode == 'en'
                    ? const Icon(Icons.check_circle, color: AppColors.lime)
                    : null,
                onTap: () async {
                  await controller.setLocale(const Locale('en'));
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editTravellerName(BuildContext context) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // Let the sheet settle before the user focuses the field. Requesting
      // focus while the modal route is still being mounted can leave an
      // inherited element with live dependents during deactivation on some
      // Android Flutter builds.
      requestFocus: false,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: AppShapes.sheet,
      builder: (_) => _TravellerNameSheet(
        initialValue: controller.travellerName == 'TRAVELER'
            ? ''
            : controller.travellerName,
      ),
    );
    if (value == null || !mounted) return;
    await controller.setTravellerName(value);
    if (!mounted || !context.mounted) return;
    _message(context, context.strings.isZh ? '用户名已保存' : 'Username saved');
  }

  void _openCloudSync(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (_) => ClipPath(
      clipper: ShapeBorderClipper(shape: AppShapes.sheet),
      child: _CloudSyncSheet(controller: controller),
    ),
  );

  void _message(
    BuildContext context,
    String message, {
    SnackBarAction? action,
  }) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Owns the text field lifecycle for the username sheet.
///
/// Keeping the controller and focus node inside the route's widget subtree is
/// important here: disposing a controller in the page immediately after
/// Navigator.pop can race the modal route's deactivation on Android and
/// trigger Flutter's `_dependents.isEmpty` assertion.
class _TravellerNameSheet extends StatefulWidget {
  const _TravellerNameSheet({required this.initialValue});

  final String initialValue;

  @override
  State<_TravellerNameSheet> createState() => _TravellerNameSheetState();
}

class _TravellerNameSheetState extends State<_TravellerNameSheet> {
  late final TextEditingController _editor;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _editor = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _editor.dispose();
    super.dispose();
  }

  void _submit() {
    if (!mounted) return;
    _focusNode.unfocus();
    Navigator.of(context).pop(_editor.text);
  }

  void _cancel() {
    if (!mounted) return;
    _focusNode.unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('enterTravellerName'), style: AppTextStyles.sectionTitle),
            const SizedBox(height: 6),
            Text(s.t('travellerNameHint'), style: AppTextStyles.bodySecondary),
            const SizedBox(height: 16),
            TextField(
              controller: _editor,
              focusNode: _focusNode,
              maxLength: 24,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: s.t('travellerName'),
                prefixIcon: const Icon(Icons.badge_outlined),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                border: ShapedInputBorder(
                  shape: AppShapes.small,
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: ShapedInputBorder(
                  shape: AppShapes.small,
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancel,
                    child: Text(s.t('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: Text(s.t('saveChanges')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: 20),
  );
}

class _ProfileAboutButton extends StatelessWidget {
  const _ProfileAboutButton({
    required this.title,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.value,
  });

  final String title;
  final String? value;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final primaryColor = enabled ? foregroundColor : AppColors.textSecondary;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: AppColors.surface,
          disabledForegroundColor: AppColors.textTertiary,
          shape: AppShapes.medium,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(icon, size: 24, color: primaryColor),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  style: AppTextStyles.body.copyWith(
                    color: primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Text(
                value!,
                style: AppTextStyles.label.copyWith(color: primaryColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UpdateDownloadDialog extends StatelessWidget {
  const _UpdateDownloadDialog({required this.progress});

  final ValueListenable<double?> progress;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: AppShapes.large,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        child: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.downloading_rounded,
                color: AppColors.lime,
                size: 30,
              ),
              const SizedBox(height: 16),
              Text(
                strings.t('downloadingUpdate'),
                style: AppTextStyles.sectionTitle,
              ),
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: value,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99),
                color: AppColors.lime,
                backgroundColor: AppColors.lime.withValues(alpha: .14),
              ),
              const SizedBox(height: 10),
              Text(
                value == null
                    ? strings.t('preparingUpdate')
                    : '${(value * 100).round()}%',
                style: AppTextStyles.label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.backgroundColor,
    this.subtitle,
    this.value,
    this.textColor = AppColors.textPrimary,
    this.secondaryTextColor = AppColors.textSecondary,
    this.wide = false,
    this.showChevron = false,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color textColor;
  final Color secondaryTextColor;
  final VoidCallback? onTap;
  final bool wide;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final label = [title, ?subtitle, ?value].join(' ');
    final content = wide
        ? Row(
            children: [
              _IconTile(icon: icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (value != null)
                SizedBox(
                  width: wide ? 116 : null,
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppTextStyles.bodySecondary.copyWith(
                      color: secondaryTextColor,
                    ),
                  ),
                ),
              if (showChevron)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: secondaryTextColor,
                  ),
                ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [_IconTile(icon: icon, color: color)],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  color: textColor,
                  fontSize: 17,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label.copyWith(
                    color: secondaryTextColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          );

    return Semantics(
      button: onTap != null,
      label: label,
      child: Container(
        constraints: BoxConstraints(minHeight: wide ? 80 : 132),
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: AppShapes.medium,
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: AppShapes.medium,
          child: Padding(padding: const EdgeInsets.all(18), child: content),
        ),
      ),
    );
  }
}

/// A page-level status strip used while the spreadsheet parser is running.
/// Keeping it in the page (instead of a SnackBar or modal route) guarantees
/// that the user sees feedback even when the scaffold is inside an IndexedStack.
class _SpreadsheetRecognizingNotice extends StatelessWidget {
  const _SpreadsheetRecognizingNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: ShapeDecoration(
          color: AppColors.surfaceElevated,
          shape: RoundedSuperellipseBorder(
            borderRadius: AppRadii.medium,
            side: BorderSide(color: AppColors.lime.withValues(alpha: .5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: AppColors.lime.withValues(alpha: .16),
                shape: AppShapes.small,
              ),
              child: const Icon(
                Icons.table_chart_rounded,
                size: 18,
                color: AppColors.lime,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.strings.t('spreadsheetRecognizing'),
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.lime,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarReadingNotice extends StatelessWidget {
  const _CalendarReadingNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: ShapeDecoration(
          color: AppColors.surfaceElevated,
          shape: RoundedSuperellipseBorder(
            borderRadius: AppRadii.medium,
            side: BorderSide(color: AppColors.purple.withValues(alpha: .5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: AppColors.purple.withValues(alpha: .16),
                shape: AppShapes.small,
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: AppColors.purple,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.strings.t('calendarReading'),
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.purple,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarPreviewSheet extends StatefulWidget {
  const _CalendarPreviewSheet({required this.result});

  final CalendarImportResult result;

  @override
  State<_CalendarPreviewSheet> createState() => _CalendarPreviewSheetState();
}

class _CalendarPreviewSheetState extends State<_CalendarPreviewSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {for (final draft in widget.result.flights) _draftKey(draft)};
  }

  List<CalendarFlightDraft> get _selectedDrafts => widget.result.flights
      .where((draft) => _selected.contains(_draftKey(draft)))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final allSelected = _selected.length == widget.result.flights.length;
    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: AppColors.background,
        shape: AppShapes.sheet,
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t('calendarImportTitle'),
                        style: AppTextStyles.sectionTitle,
                      ),
                    ),
                    IconButton(
                      tooltip: s.t('cancel'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  '${s.t('calendarEventsRead').replaceFirst('{count}', '${widget.result.eventsRead}')} · '
                  '${s.t('calendarFlightsFound').replaceFirst('{count}', '${widget.result.flights.length}')}',
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _selected = allSelected
                          ? <String>{}
                          : {
                              for (final draft in widget.result.flights)
                                _draftKey(draft),
                            };
                    }),
                    icon: Icon(
                      allSelected
                          ? Icons.remove_done_rounded
                          : Icons.done_all_rounded,
                      size: 18,
                    ),
                    label: Text(s.t(allSelected ? 'deselectAll' : 'selectAll')),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.separated(
                    itemCount: widget.result.flights.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final draft = widget.result.flights[index];
                      final selected = _selected.contains(_draftKey(draft));
                      final departureName = localizedAirportCardName(
                        draft.departureAirport,
                      );
                      final arrivalName = localizedAirportCardName(
                        draft.arrivalAirport,
                      );
                      final departureDate = DateFormat('yyyy-MM-dd HH:mm')
                          .format(draft.departedAt);
                      final arrivalDate = DateFormat('yyyy-MM-dd HH:mm')
                          .format(draft.arrivedAt);
                      return Semantics(
                        button: true,
                        selected: selected,
                        label:
                            '${draft.flightNumber} $departureName ${s.t('arrival')} $arrivalName',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() {
                              final key = _draftKey(draft);
                              if (selected) {
                                _selected.remove(key);
                              } else {
                                _selected.add(key);
                              }
                            }),
                            customBorder: AppShapes.medium,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                              decoration: ShapeDecoration(
                                color: selected
                                    ? AppColors.surface
                                    : AppColors.surfaceElevated,
                                shape: RoundedSuperellipseBorder(
                                  borderRadius: AppRadii.medium,
                                  side: BorderSide(
                                    color: selected
                                        ? AppColors.lime.withValues(alpha: .72)
                                        : AppColors.border,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${draft.airline}  ${draft.flightNumber}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              draft.status ==
                                                      FlightStatus.upcoming
                                                  ? s.t('upcoming')
                                                  : s.t('completed'),
                                              style: AppTextStyles.label
                                                  .copyWith(
                                                    color:
                                                        draft.status ==
                                                            FlightStatus
                                                                .upcoming
                                                        ? AppColors.purple
                                                        : AppColors.lime,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$departureName → $arrivalName',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.bodySecondary,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$departureDate  →  $arrivalDate',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.label,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_formatSpreadsheetDuration(context, draft.durationMinutes)} · ${draft.distanceKm.round()} km',
                                          style: AppTextStyles.label.copyWith(
                                            color: AppColors.purple,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Checkbox(
                                    value: selected,
                                    onChanged: (_) => setState(() {
                                      final key = _draftKey(draft);
                                      if (selected) {
                                        _selected.remove(key);
                                      } else {
                                        _selected.add(key);
                                      }
                                    }),
                                    activeColor: AppColors.lime,
                                    checkColor: Colors.black,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: s.t('calendarConfirm'),
                  icon: Icons.event_available_rounded,
                  onPressed: _selectedDrafts.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selectedDrafts),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _draftKey(CalendarFlightDraft draft) =>
      '${draft.flightNumber}|${draft.departedAt.toIso8601String()}|${draft.departureIata}|${draft.arrivalIata}';
}

class _SpreadsheetPreviewSheet extends StatefulWidget {
  const _SpreadsheetPreviewSheet({required this.result, required this.preview});

  final SpreadsheetImportResult result;
  final FlightImportPreview preview;

  @override
  State<_SpreadsheetPreviewSheet> createState() =>
      _SpreadsheetPreviewSheetState();
}

class _SpreadsheetPreviewSheetState extends State<_SpreadsheetPreviewSheet> {
  int _selectedTab = 0;

  SpreadsheetImportResult get result => widget.result;

  List<SpreadsheetFlightRow> get _conflictRows {
    final ids = widget.preview.conflictingFlights
        .map((flight) => flight.id)
        .toSet();
    return result.rows
        .where((row) => ids.contains(row.flight.id))
        .toList(growable: false);
  }

  List<SpreadsheetFlightRow> get _readyRows {
    final ids = widget.preview.conflictingFlights
        .map((flight) => flight.id)
        .toSet();
    return result.rows
        .where((row) => !ids.contains(row.flight.id))
        .toList(growable: false);
  }

  List<SpreadsheetFlightRow> get _visibleRows =>
      _selectedTab == 2 ? _conflictRows : _readyRows;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: AppColors.background,
        shape: AppShapes.sheet,
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.lime.withValues(alpha: .14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.table_chart_outlined,
                        color: AppColors.lime,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.t('spreadsheetImportTitle'),
                            style: AppTextStyles.sectionTitle.copyWith(
                              fontSize: 24,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${s.t('spreadsheetSheet')} · ${result.sheetName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.label.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: s.t('cancel'),
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _SpreadsheetReviewTabButton(
                        label: s.t('spreadsheetValidRows'),
                        count: _readyRows.length,
                        color: const Color(0xFFA8D7AF),
                        selected: _selectedTab == 0,
                        onTap: () => setState(() => _selectedTab = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpreadsheetReviewTabButton(
                        label: s.t('spreadsheetIssueRows'),
                        count: result.issues.length,
                        color: const Color(0xFFE7C6BF),
                        selected: _selectedTab == 1,
                        onTap: () => setState(() => _selectedTab = 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpreadsheetReviewTabButton(
                        label: s.t('spreadsheetConflicts'),
                        count: _conflictRows.length,
                        color: const Color(0xFFB9A9F2),
                        selected: _selectedTab == 2,
                        onTap: () => setState(() => _selectedTab = 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _selectedTab == 1
                      ? result.issues.isEmpty
                            ? _SpreadsheetReviewEmpty(
                                icon: Icons.check_circle_outline_rounded,
                                message: s.t('spreadsheetNoIssues'),
                              )
                            : SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _SpreadsheetIssuesPanel(
                                  issues: result.issues,
                                  hint: s.t('spreadsheetIssuesHint'),
                                ),
                              )
                      : _visibleRows.isEmpty
                      ? _SpreadsheetReviewEmpty(
                          icon: _selectedTab == 2
                              ? Icons.layers_clear_outlined
                              : Icons.table_rows_outlined,
                          message: s.t(
                            _selectedTab == 2
                                ? 'spreadsheetNoConflicts'
                                : 'spreadsheetNoReadyRows',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 4),
                          itemCount: _visibleRows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _visibleRows[index];
                            final flight = item.flight;
                            final date = DateFormat('yyyy-MM-dd HH:mm')
                                .format(flight.departedAt.toLocal());
                            final isConflict = _selectedTab == 2;
                            return _SpreadsheetFlightCard(
                              item: item,
                              date: date,
                              duration:
                                  '${s.t('flightDuration')} · ${_formatSpreadsheetDuration(context, flight.durationMinutes)}',
                              statusLabel: isConflict
                                  ? s.t('spreadsheetConflicts')
                                  : s.t(
                                      flight.isUpcoming
                                          ? 'upcoming'
                                          : 'completed',
                                    ),
                              statusColor: isConflict
                                  ? AppColors.purple
                                  : flight.isUpcoming
                                  ? AppColors.purple
                                  : AppColors.lime,
                              ambiguousAirportMessage: item.hasAmbiguousAirport
                                  ? s.t('spreadsheetAmbiguousAirport')
                                  : null,
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: s.t('spreadsheetConfirm'),
                  icon: Icons.file_download_done_rounded,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatSpreadsheetDuration(BuildContext context, int? minutes) {
  if (minutes == null || minutes <= 0) {
    return context.strings.t('durationPending');
  }
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (context.strings.isZh) {
    if (hours == 0) return '${remaining.toString()}分';
    if (remaining == 0) return '${hours.toString()}小时';
    return '${hours.toString()}小时${remaining.toString()}分';
  }
  if (hours == 0) return '${remaining}m';
  if (remaining == 0) return '${hours}h';
  return '${hours}h ${remaining}m';
}

class _SpreadsheetReviewTabButton extends StatelessWidget {
  const _SpreadsheetReviewTabButton({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected
        ? color
        : Color.alphaBlend(
            color.withValues(alpha: .18),
            AppColors.surfaceElevated,
          );
    final countColor = selected ? Colors.black : color;
    final labelColor = selected ? Colors.black : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label $count',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: AppShapes.medium,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 82,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: ShapeDecoration(
              color: backgroundColor,
              shape: AppShapes.medium,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  count.toString(),
                  style: TextStyle(
                    color: countColor,
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpreadsheetIssuesPanel extends StatelessWidget {
  const _SpreadsheetIssuesPanel({required this.issues, required this.hint});

  final List<SpreadsheetImportIssue> issues;
  final String hint;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: ShapeDecoration(
          color: AppColors.danger.withValues(alpha: .08),
          shape: AppShapes.medium,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 124),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: issues.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final issue = issues[index];
                    return Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${issue.rowNumber}  ',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: issue.message,
                            style: AppTextStyles.label,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        hint,
        style: AppTextStyles.label.copyWith(color: AppColors.textTertiary),
      ),
    ],
  );
}

class _SpreadsheetFlightCard extends StatelessWidget {
  const _SpreadsheetFlightCard({
    required this.item,
    required this.date,
    required this.duration,
    required this.statusLabel,
    required this.statusColor,
    this.ambiguousAirportMessage,
  });

  final SpreadsheetFlightRow item;
  final String date;
  final String duration;
  final String statusLabel;
  final Color statusColor;
  final String? ambiguousAirportMessage;

  @override
  Widget build(BuildContext context) {
    final flight = item.flight;
    final airline = (flight.airline ?? '').trim();
    final flightNumber = (flight.flightNumber ?? '').trim();
    final title = [
      airline,
      flightNumber,
    ].where((value) => value.isNotEmpty).join('  ');
    return Semantics(
      container: true,
      label: [
        title,
        flight.departureIata,
        item.departureAirportName,
        context.strings.t('arrival'),
        flight.arrivalIata,
        item.arrivalAirportName,
        date,
        duration,
      ].join(' '),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: ShapeDecoration(
          color: AppColors.surfaceElevated,
          shape: AppShapes.medium,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SpreadsheetRowNumber(number: item.rowNumber),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      title.isEmpty ? '—' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SpreadsheetStatusTag(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: 14),
            _SpreadsheetRouteBlock(
              departureCode: flight.departureIata,
              departureName: item.departureAirportName,
              arrivalCode: flight.arrivalIata,
              arrivalName: item.arrivalAirportName,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _SpreadsheetMetaItem(
                  icon: Icons.calendar_today_rounded,
                  text: date,
                ),
                _SpreadsheetMetaItem(
                  icon: Icons.schedule_rounded,
                  text: duration,
                  color: AppColors.purple,
                ),
              ],
            ),
            if (ambiguousAirportMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: ShapeDecoration(
                  color: AppColors.danger.withValues(alpha: .08),
                  shape: AppShapes.small,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.danger,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ambiguousAirportMessage!,
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpreadsheetRowNumber extends StatelessWidget {
  const _SpreadsheetRowNumber({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.lime.withValues(alpha: .14),
      shape: BoxShape.circle,
    ),
    child: Text(
      '$number',
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _SpreadsheetStatusTag extends StatelessWidget {
  const _SpreadsheetStatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: AppRadii.pill,
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.label.copyWith(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SpreadsheetRouteBlock extends StatelessWidget {
  const _SpreadsheetRouteBlock({
    required this.departureCode,
    required this.departureName,
    required this.arrivalCode,
    required this.arrivalName,
  });

  final String departureCode;
  final String departureName;
  final String arrivalCode;
  final String arrivalName;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 22,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.flight_takeoff_rounded,
              color: AppColors.lime,
              size: 18,
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(vertical: 3),
              color: AppColors.border,
            ),
            const Icon(
              Icons.flight_land_rounded,
              color: AppColors.purple,
              size: 18,
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SpreadsheetAirportLine(code: departureCode, name: departureName),
            const SizedBox(height: 10),
            _SpreadsheetAirportLine(code: arrivalCode, name: arrivalName),
          ],
        ),
      ),
    ],
  );
}

class _SpreadsheetAirportLine extends StatelessWidget {
  const _SpreadsheetAirportLine({required this.code, required this.name});

  final String code;
  final String name;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: code.isEmpty ? '—' : code,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (name.trim().isNotEmpty)
          TextSpan(
            text: '  ${name.trim()}',
            style: AppTextStyles.bodySecondary,
          ),
      ],
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

class _SpreadsheetMetaItem extends StatelessWidget {
  const _SpreadsheetMetaItem({
    required this.icon,
    required this.text,
    this.color = AppColors.textSecondary,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: AppTextStyles.label.copyWith(
            color: color,
            fontWeight: color == AppColors.purple
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _SpreadsheetReviewEmpty extends StatelessWidget {
  const _SpreadsheetReviewEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySecondary,
          ),
        ],
      ),
    ),
  );
}

class _SpreadsheetProgressDialog extends StatelessWidget {
  const _SpreadsheetProgressDialog({required this.progress});

  final ValueNotifier<double?> progress;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return ValueListenableBuilder<double?>(
      valueListenable: progress,
      builder: (context, value, _) {
        final normalized = value?.clamp(0.0, 1.0).toDouble();
        final activeStep = normalized == null
            ? 0
            : normalized < .5
            ? 0
            : normalized < .9
            ? 1
            : 2;
        final title = s.t('spreadsheetImporting');
        final hint = s.t('spreadsheetImportingHint');
        return Dialog(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          shape: RoundedSuperellipseBorder(
            borderRadius: AppRadii.large,
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 270),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    liveRegion: true,
                    label: title,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.sectionTitle,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 104,
                    height: 104,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: normalized,
                          strokeWidth: 5,
                          color: AppColors.lime,
                          backgroundColor: AppColors.surfaceElevated,
                        ),
                        const SizedBox(
                          width: 54,
                          height: 54,
                          child: CustomPaint(
                            painter: _SpreadsheetTablePainter(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (normalized != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${(normalized * 100).round()}%',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.lime,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _SpreadsheetStageRow(activeIndex: activeStep),
                  const SizedBox(height: 14),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpreadsheetStageRow extends StatelessWidget {
  const _SpreadsheetStageRow({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final labels = [
      s.t('spreadsheetStageReading'),
      s.t('spreadsheetStageMatching'),
      s.t('spreadsheetStageReady'),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          if (index > 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Container(
                  height: 1,
                  color: index <= activeIndex
                      ? AppColors.lime.withValues(alpha: .48)
                      : AppColors.border,
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index <= activeIndex
                        ? AppColors.lime
                        : AppColors.surfaceElevated,
                    border: Border.all(
                      color: index <= activeIndex
                          ? AppColors.lime
                          : AppColors.border,
                    ),
                  ),
                  child: index < activeIndex
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.black,
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: index == activeIndex
                                ? Colors.black
                                : AppColors.textTertiary,
                          ),
                        ),
                ),
                const SizedBox(height: 5),
                Text(
                  labels[index],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 11,
                    color: index <= activeIndex
                        ? AppColors.textSecondary
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SpreadsheetTablePainter extends CustomPainter {
  const _SpreadsheetTablePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final softInk = Paint()
      ..color = AppColors.textSecondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final sheet = Rect.fromLTWH(7, 3, 40, 48);
    canvas.drawRRect(
      RRect.fromRectAndRadius(sheet, const Radius.circular(6)),
      ink,
    );
    final fold = Path()
      ..moveTo(34, 3)
      ..lineTo(47, 16)
      ..lineTo(34, 16)
      ..close();
    canvas.drawPath(fold, ink);
    for (var row = 0; row <= 3; row++) {
      final y = 20.0 + row * 8;
      canvas.drawLine(Offset(13, y), Offset(41, y), softInk);
    }
    for (var column = 0; column <= 2; column++) {
      final x = 13.0 + column * 9.3;
      canvas.drawLine(Offset(x, 20), Offset(x, 44), softInk);
    }
  }

  @override
  bool shouldRepaint(covariant _SpreadsheetTablePainter oldDelegate) => false;
}

class _CloudSyncSheet extends StatefulWidget {
  const _CloudSyncSheet({required this.controller});

  final AppController controller;

  @override
  State<_CloudSyncSheet> createState() => _CloudSyncSheetState();
}

class _CloudSyncSheetState extends State<_CloudSyncSheet> {
  late final TextEditingController _endpointController;
  late final TextEditingController _credentialController;
  int _mode = 0;
  bool _busy = false;
  String? _error;
  String? _newRecoveryCode;

  CloudSyncService get _cloud => widget.controller.cloudSync;

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(
      text: _cloud.state.endpoint ?? '',
    );
    _credentialController = TextEditingController();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _credentialController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return ListenableBuilder(
      listenable: _cloud,
      builder: (context, _) {
        final state = _cloud.state;
        final insets = MediaQuery.viewInsetsOf(context);
        return Material(
          color: AppColors.background,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + insets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.lime.withValues(alpha: .14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.cloud_outlined,
                          color: AppColors.lime,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.t('cloudSyncTitle'),
                          style: AppTextStyles.sectionTitle.copyWith(
                            fontSize: 24,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: s.t('close'),
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    s.t('cloudSetupHint'),
                    style: AppTextStyles.bodySecondary,
                  ),
                  const SizedBox(height: 18),
                  if (state.isConfigured) ...[
                    _ConnectedCloudCard(
                      state: state,
                      onChangeEndpoint: _changeEndpoint,
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: state.isSyncing
                          ? s.t('cloudSyncing')
                          : s.t('localToCloud'),
                      icon: Icons.cloud_upload_outlined,
                      onPressed: state.isSyncing || _busy
                          ? null
                          : _syncLocalToCloud,
                    ),
                    const SizedBox(height: 10),
                    Text(s.t('localToCloudHint'), style: AppTextStyles.label),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: _CloudSecondaryButton(
                        onPressed: state.isSyncing || _busy
                            ? null
                            : _restoreFromCloud,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: s.t('restoreFromCloud'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.t('restoreFromCloudHint'),
                      style: AppTextStyles.label,
                    ),
                    const SizedBox(height: 10),
                    if (state.hasRecoveryCode || _newRecoveryCode != null)
                      SizedBox(
                        width: double.infinity,
                        child: _CloudSecondaryButton(
                          onPressed: _busy ? null : _showRecoveryCode,
                          icon: const Icon(Icons.key_outlined),
                          label: s.t('viewRecoveryCode'),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _ErrorNotice(text: _error!),
                    ],
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _busy ? null : _disconnect,
                        child: Text(
                          s.t('disconnectCloud'),
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ),
                  ] else ...[
                    AppSegmentedControl(
                      labels: [s.t('createCloud'), s.t('restoreCloud')],
                      selectedIndex: _mode,
                      pill: true,
                      onChanged: _busy
                          ? (_) {}
                          : (value) => setState(() {
                              _mode = value;
                              _error = null;
                              _credentialController.clear();
                            }),
                    ),
                    const SizedBox(height: 18),
                    _CloudTextField(
                      controller: _endpointController,
                      label: s.t('cloudEndpoint'),
                      hint: s.t('cloudEndpointHint'),
                      prefixIcon: Icons.link_rounded,
                      keyboardType: TextInputType.url,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 12),
                    _CloudTextField(
                      controller: _credentialController,
                      label: _mode == 0
                          ? s.t('cloudBootstrapSecret')
                          : s.t('cloudRecoveryCode'),
                      hint: _mode == 0
                          ? s.t('cloudBootstrapHint')
                          : s.t('cloudRecoveryHint'),
                      prefixIcon: _mode == 0
                          ? Icons.key_outlined
                          : Icons.vpn_key_outlined,
                      obscureText: _mode == 0,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.none,
                    ),
                    const SizedBox(height: 18),
                    if (_mode == 0)
                      _SecurityNotice(text: s.t('recoveryCodeWarning')),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _ErrorNotice(text: _error!),
                    ],
                    const SizedBox(height: 18),
                    PrimaryButton(
                      label: _busy ? s.t('cloudSyncing') : s.t('connectCloud'),
                      icon: _busy ? Icons.sync_rounded : Icons.cloud_outlined,
                      onPressed: _busy ? null : _connect,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _connect() async {
    final endpoint = _endpointController.text.trim();
    final credential = _credentialController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_mode == 0) {
        _newRecoveryCode = await _cloud.createVault(
          endpoint: endpoint,
          bootstrapSecret: credential,
          deviceName: 'Android',
        );
        // A newly created vault has no remote snapshot yet. Seed it once with
        // the current local data, while restore mode remains explicit and
        // never overwrites the cloud implicitly.
        await _cloud.syncLocalToCloud();
      } else {
        await _cloud.restoreCloud(
          endpoint: endpoint,
          recoveryCode: credential,
          deviceName: 'Android',
        );
      }
      _credentialController.clear();
      if (mounted) {
        _message(
          context,
          _mode == 0
              ? context.strings.t('cloudSynced')
              : context.strings.t('cloudReady'),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _errorText(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncLocalToCloud() async {
    try {
      await _cloud.syncLocalToCloud();
      if (mounted) {
        _message(context, context.strings.t('cloudSynced'));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
      rethrow;
    }
  }

  Future<void> _restoreFromCloud() async {
    final s = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('restoreCloudTitle')),
        content: Text(s.t('restoreCloudMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.t('restoreCloudConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _cloud.restoreCloudToLocal();
      if (mounted) _message(context, s.t('cloudRestored'));
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final s = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('disconnectCloud')),
        content: Text(s.t('disconnectCloudHint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(s.t('disconnectCloud')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _cloud.disconnect();
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeEndpoint() async {
    final s = context.strings;
    final endpointController = TextEditingController();
    final endpoint = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('changeCloudEndpointTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t('changeCloudEndpointHint'),
              style: AppTextStyles.bodySecondary,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: endpointController,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: InputDecoration(
                labelText: s.t('cloudEndpoint'),
                hintText: 'https://flight-footprint-sync-pages.pages.dev',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, endpointController.text.trim()),
            child: Text(s.t('changeCloudEndpointConfirm')),
          ),
        ],
      ),
    );
    endpointController.dispose();
    if (endpoint == null || endpoint.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _cloud.changeEndpoint(endpoint);
      await _cloud.syncLocalToCloud();
      if (mounted) _message(context, context.strings.t('cloudSynced'));
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRecoveryCode() async {
    final code = _newRecoveryCode ?? await _cloud.recoveryCode();
    if (!mounted) return;
    if (code == null || code.isEmpty) {
      _message(context, context.strings.t('noRecoveryCode'));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.strings.t('cloudRecoveryCode')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.strings.t('recoveryCodeWarning'),
              style: AppTextStyles.bodySecondary,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                _message(context, context.strings.t('recoveryCodeSaved'));
              }
            },
            child: Text(context.strings.t('copyRecoveryCode')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.strings.t('close')),
          ),
        ],
      ),
    );
  }

  String _errorText(Object error) {
    if (error is CloudSyncException) return error.message;
    return '${context.strings.t('operationFailed')}: $error';
  }

  void _message(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _ConnectedCloudCard extends StatelessWidget {
  const _ConnectedCloudCard({
    required this.state,
    required this.onChangeEndpoint,
  });

  final CloudSyncState state;
  final VoidCallback onChangeEndpoint;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final lastSynced = state.lastSyncedAt == null
        ? s.t('neverSynced')
        : state.lastSyncedAt!.toLocal().toString().substring(0, 16);
    final status = switch (state.status) {
      CloudSyncStatus.syncing => s.t('cloudSyncing'),
      CloudSyncStatus.synced => s.t('cloudSynced'),
      CloudSyncStatus.error => s.t('cloudSyncFailed'),
      CloudSyncStatus.ready => s.t('cloudReady'),
      CloudSyncStatus.disconnected => s.t('notConfigured'),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: ShapeDecoration(
        color: AppColors.surfaceElevated,
        shape: AppShapes.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_done_rounded, color: AppColors.lime),
              const SizedBox(width: 10),
              Text(status, style: AppTextStyles.sectionTitle),
            ],
          ),
          const SizedBox(height: 14),
          Text(s.t('cloudEndpoint'), style: AppTextStyles.label),
          const SizedBox(height: 4),
          SelectableText(
            state.endpoint ?? '',
            maxLines: 2,
            style: AppTextStyles.bodySecondary,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: state.isSyncing ? null : onChangeEndpoint,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(s.t('changeCloudEndpoint')),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.lime,
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CloudMeta(label: s.t('lastSynced'), value: lastSynced),
              ),
              _CloudMeta(label: 'Revision', value: '${state.revision}'),
            ],
          ),
          if (state.message != null) ...[
            const SizedBox(height: 10),
            Text(
              state.message!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _CloudMeta extends StatelessWidget {
  const _CloudMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.label),
      const SizedBox(height: 3),
      Text(value, style: AppTextStyles.bodySecondary),
    ],
  );
}

class _CloudSecondaryButton extends StatelessWidget {
  const _CloudSecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 50),
        backgroundColor: AppColors.surfaceElevated,
        foregroundColor: AppColors.textPrimary,
        disabledBackgroundColor: AppColors.surface,
        disabledForegroundColor: AppColors.textTertiary,
        shape: AppShapes.large,
      ),
    ),
  );
}

class _CloudTextField extends StatelessWidget {
  const _CloudTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.enabled = true,
    this.obscureText = false,
    this.prefixIcon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final bool obscureText;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    obscureText: obscureText,
    keyboardType: keyboardType,
    autocorrect: false,
    textCapitalization: textCapitalization,
    style: AppTextStyles.body,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      hintMaxLines: 2,
      filled: true,
      fillColor: AppColors.surfaceElevated,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: AppColors.textTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: AppTextStyles.label,
      floatingLabelStyle: const TextStyle(
        color: AppColors.lime,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: AppTextStyles.bodySecondary.copyWith(fontSize: 13),
      border: ShapedInputBorder(
        shape: AppShapes.medium,
        borderSide: BorderSide.none,
      ),
      enabledBorder: ShapedInputBorder(
        shape: AppShapes.medium,
        borderSide: BorderSide.none,
      ),
      focusedBorder: ShapedInputBorder(
        shape: AppShapes.medium,
        borderSide: const BorderSide(color: AppColors.lime, width: 1.5),
      ),
    ),
  );
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: ShapeDecoration(
      color: AppColors.lime.withValues(alpha: .08),
      shape: AppShapes.medium,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield_outlined, color: AppColors.lime, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySecondary.copyWith(fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: ShapeDecoration(
      color: AppColors.danger.withValues(alpha: .1),
      shape: RoundedSuperellipseBorder(
        borderRadius: AppRadii.small,
        side: BorderSide(color: AppColors.danger.withValues(alpha: .32)),
      ),
    ),
    child: Text(text, style: const TextStyle(color: AppColors.danger)),
  );
}

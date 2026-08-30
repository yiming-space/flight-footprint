import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_links.dart';
import '../../app/app_controller.dart';
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
  const ProfilePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  AppController get controller => widget.controller;

  bool _isRecognizingSpreadsheet = false;
  bool _isReadingCalendar = false;
  bool _isCheckingForUpdates = false;
  AppUpdateResult? _updateResult;
  final AppUpdateService _updateService = AppUpdateService();

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
          SliverToBoxAdapter(
            child: PageHeader(
              title: s.t('profile'),
              subtitle: s.t('localFirst'),
            ),
          ),
          if (_isRecognizingSpreadsheet)
            const SliverToBoxAdapter(child: _SpreadsheetRecognizingNotice()),
          if (_isReadingCalendar)
            const SliverToBoxAdapter(child: _CalendarReadingNotice()),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              AppSpacing.bottomBarClearance(context),
            ),
            sliver: SliverList.list(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB4A5EE),
                    borderRadius: BorderRadius.circular(30),
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
                            fontSize: 34,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text(s.t('localData'), style: AppTextStyles.sectionTitle),
                const SizedBox(height: 12),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      DisclosureRow(
                        title: s.t('exportBackup'),
                        subtitle: 'JSON',
                        leading: const _IconTile(
                          icon: Icons.ios_share_rounded,
                          color: AppColors.lime,
                        ),
                        onTap: () => _export(context),
                      ),
                      const Divider(height: 1),
                      DisclosureRow(
                        title: s.t('importWebData'),
                        subtitle: s.t('importWebHint'),
                        leading: const _IconTile(
                          icon: Icons.file_download_outlined,
                          color: AppColors.purple,
                        ),
                        onTap: () => _import(context),
                      ),
                      const Divider(height: 1),
                      DisclosureRow(
                        title: s.t('importExcel'),
                        subtitle: s.t('importExcelHint'),
                        leading: const _IconTile(
                          icon: Icons.table_view_rounded,
                          color: AppColors.lime,
                        ),
                        onTap: () => _importSpreadsheet(context),
                      ),
                      const Divider(height: 1),
                      DisclosureRow(
                        title: s.t('importCalendar'),
                        subtitle: s.t('importCalendarHint'),
                        leading: const _IconTile(
                          icon: Icons.calendar_month_rounded,
                          color: AppColors.purple,
                        ),
                        onTap: () => _importCalendar(context),
                      ),
                      const Divider(height: 1),
                      ListenableBuilder(
                        listenable: controller.cloudSync,
                        builder: (context, _) {
                          final cloud = controller.cloudSync.state;
                          final value = switch (cloud.status) {
                            CloudSyncStatus.syncing => s.t('cloudSyncing'),
                            CloudSyncStatus.synced => s.t('cloudSynced'),
                            CloudSyncStatus.error => s.t('cloudSyncFailed'),
                            CloudSyncStatus.ready => s.t('cloudReady'),
                            CloudSyncStatus.disconnected => s.t(
                              'notConfigured',
                            ),
                          };
                          final color = cloud.isConfigured
                              ? AppColors.lime
                              : AppColors.textTertiary;
                          return DisclosureRow(
                            title: s.t('cloudSync'),
                            value: value,
                            leading: _IconTile(
                              icon: cloud.isConfigured
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_outlined,
                              color: color,
                            ),
                            onTap: () => _openCloudSync(context),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Text(s.t('settings'), style: AppTextStyles.sectionTitle),
                const SizedBox(height: 12),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      DisclosureRow(
                        title: s.t('travellerName'),
                        value: controller.travellerName == 'TRAVELER'
                            ? s.t('travellerNameEmpty')
                            : controller.travellerName,
                        leading: const _IconTile(
                          icon: Icons.badge_outlined,
                          color: AppColors.lime,
                        ),
                        onTap: () => _editTravellerName(context),
                      ),
                      const Divider(height: 1),
                      DisclosureRow(
                        title: s.t('language'),
                        value: controller.locale.languageCode == 'zh'
                            ? s.t('chinese')
                            : s.t('english'),
                        leading: const _IconTile(
                          icon: Icons.translate_rounded,
                          color: AppColors.lime,
                        ),
                        onTap: () => _language(context),
                      ),
                      const Divider(height: 1),
                      DisclosureRow(
                        title: s.t('units'),
                        value: 'km',
                        leading: const _IconTile(
                          icon: Icons.straighten_rounded,
                          color: AppColors.purple,
                        ),
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Text(s.t('about'), style: AppTextStyles.sectionTitle),
                const SizedBox(height: 12),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        child: Text(
                          'Flight Footprint',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Text(
                          s.t('version'),
                          style: AppTextStyles.bodySecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Divider(height: 1),
                      DisclosureRow(
                        title: s.t('checkForUpdates'),
                        subtitle: _updateSubtitle(context),
                        value: _updateValue(),
                        leading: const _IconTile(
                          icon: Icons.system_update_alt_rounded,
                          color: AppColors.lime,
                        ),
                        onTap: () => _checkForUpdates(context),
                      ),
                      const Divider(height: 1),
                      DisclosureRow(
                        title: s.t('githubProject'),
                        subtitle: AppLinks.githubRepository == null
                            ? s.t('githubProjectNotConfigured')
                            : s.t('githubProjectHint'),
                        leading: const _IconTile(
                          icon: Icons.code_rounded,
                          color: AppColors.purple,
                        ),
                        showChevron: AppLinks.githubRepository != null,
                        onTap: AppLinks.githubRepository == null
                            ? null
                            : () => _openExternalUrl(
                                context,
                                AppLinks.githubRepository!,
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.lg,
                        ),
                        child: Text(
                          s.t('privacy'),
                          style: AppTextStyles.bodySecondary,
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

  Future<void> _checkForUpdates(BuildContext context) async {
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

    switch (result.status) {
      case UpdateCheckStatus.available:
        _message(
          context,
          '${strings.t('updateAvailable')} · v${result.latestVersion}',
          action: result.releaseUrl == null
              ? null
              : SnackBarAction(
                  label: strings.t('openRelease'),
                  onPressed: () =>
                      _openExternalUrl(context, result.releaseUrl!),
                ),
        );
      case UpdateCheckStatus.upToDate:
        _message(context, strings.t('upToDate'));
      case UpdateCheckStatus.notConfigured:
        _message(context, strings.t('githubProjectNotConfigured'));
      case UpdateCheckStatus.unavailable:
        _message(context, strings.t('updateCheckFailed'));
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
        // Let the page-level notice paint before the synchronous parser starts.
        await WidgetsBinding.instance.endOfFrame;
        parsed = controller.parseFlightSpreadsheet(
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
    builder: (_) => FractionallySizedBox(
      heightFactor: .9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: _CloudSyncSheet(controller: controller),
      ),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
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
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: AppRadii.medium,
          border: Border.all(color: AppColors.lime.withValues(alpha: .5)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.lime.withValues(alpha: .16),
                borderRadius: AppRadii.small,
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
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: AppRadii.medium,
          border: Border.all(color: AppColors.purple.withValues(alpha: .5)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: .16),
                borderRadius: AppRadii.small,
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
                            borderRadius: AppRadii.medium,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.surface
                                    : AppColors.surfaceElevated,
                                borderRadius: AppRadii.medium,
                                border: Border.all(
                                  color: selected
                                      ? AppColors.lime.withValues(alpha: .72)
                                      : AppColors.border,
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

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
                        s.t('spreadsheetImportTitle'),
                        style: AppTextStyles.sectionTitle,
                      ),
                    ),
                    IconButton(
                      tooltip: s.t('cancel'),
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  '${s.t('spreadsheetSheet')}：${result.sheetName}',
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _SpreadsheetReviewTabButton(
                        label: s.t('spreadsheetValidRows'),
                        count: _readyRows.length,
                        color: AppColors.lime,
                        selected: _selectedTab == 0,
                        onTap: () => setState(() => _selectedTab = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpreadsheetReviewTabButton(
                        label: s.t('spreadsheetIssueRows'),
                        count: result.issues.length,
                        color: const Color(0xFFFFD8D0),
                        selected: _selectedTab == 1,
                        onTap: () => setState(() => _selectedTab = 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpreadsheetReviewTabButton(
                        label: s.t('spreadsheetConflicts'),
                        count: _conflictRows.length,
                        color: const Color(0xFFC9B8FF),
                        selected: _selectedTab == 2,
                        onTap: () => setState(() => _selectedTab = 2),
                      ),
                    ),
                  ],
                ),
                if (_selectedTab == 1 && result.issues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 112),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: .12),
                      borderRadius: AppRadii.medium,
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: .35),
                      ),
                    ),
                    child: ListView.builder(
                      itemCount: result.issues.length,
                      itemBuilder: (context, index) {
                        final issue = result.issues[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${issue.rowNumber}：${issue.message}',
                            style: AppTextStyles.label,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.t('spreadsheetIssuesHint'),
                    style: AppTextStyles.label,
                  ),
                ],
                if (_selectedTab == 1 && result.issues.isEmpty)
                  Expanded(
                    child: _SpreadsheetReviewEmpty(
                      icon: Icons.check_circle_outline_rounded,
                      message: s.t('spreadsheetNoIssues'),
                    ),
                  ),
                const SizedBox(height: 12),
                if (_selectedTab != 1)
                  Expanded(
                    child: ListView.separated(
                      itemCount:
                          (_selectedTab == 2 ? _conflictRows : _readyRows)
                              .length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = (_selectedTab == 2
                            ? _conflictRows
                            : _readyRows)[index];
                        final flight = item.flight;
                        final date = DateFormat('yyyy-MM-dd HH:mm')
                            .format(flight.departedAt.toLocal());
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadii.medium,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.lime.withValues(alpha: .16),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${item.rowNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${flight.airline ?? ''}  ${flight.flightNumber ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${flight.departureIata}  ${item.departureAirportName}\n'
                                      '→  ${flight.arrivalIata}  ${item.arrivalAirportName}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodySecondary,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(date, style: AppTextStyles.label),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${s.t('flightDuration')} · ${_formatSpreadsheetDuration(context, flight.durationMinutes)}',
                                      style: AppTextStyles.label.copyWith(
                                        color: AppColors.purple,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (item.hasAmbiguousAirport)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          s.t('spreadsheetAmbiguousAirport'),
                                          style: AppTextStyles.label.copyWith(
                                            color: AppColors.danger,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label $count',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.medium,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadii.medium,
            border: Border.all(
              color: selected ? Colors.black : Colors.transparent,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
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
          shape: RoundedRectangleBorder(
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
              padding: EdgeInsets.fromLTRB(20, 16, 20, 28 + insets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.t('cloudSyncTitle'),
                          style: AppTextStyles.sectionTitle,
                        ),
                      ),
                      IconButton(
                        tooltip: s.t('close'),
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.t('cloudSetupHint'),
                    style: AppTextStyles.bodySecondary,
                  ),
                  const SizedBox(height: 20),
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
                      child: OutlinedButton.icon(
                        onPressed: state.isSyncing || _busy
                            ? null
                            : _restoreFromCloud,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: Text(s.t('restoreFromCloud')),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(44, 50),
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadii.large,
                          ),
                        ),
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
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _showRecoveryCode,
                          icon: const Icon(Icons.key_outlined),
                          label: Text(s.t('viewRecoveryCode')),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 50),
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.border),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppRadii.large,
                            ),
                          ),
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadii.medium,
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

class _CloudTextField extends StatelessWidget {
  const _CloudTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final bool obscureText;
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
      fillColor: AppColors.surface,
      labelStyle: AppTextStyles.label,
      hintStyle: AppTextStyles.bodySecondary.copyWith(fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: AppRadii.medium,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadii.medium,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadii.medium,
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
    decoration: BoxDecoration(
      color: AppColors.lime.withValues(alpha: .08),
      borderRadius: AppRadii.small,
      border: Border.all(color: AppColors.lime.withValues(alpha: .22)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield_outlined, color: AppColors.lime, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTextStyles.bodySecondary)),
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
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: .1),
      borderRadius: AppRadii.small,
      border: Border.all(color: AppColors.danger.withValues(alpha: .32)),
    ),
    child: Text(text, style: const TextStyle(color: AppColors.danger)),
  );
}

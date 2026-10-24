import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_links.dart';
import '../../app/app_controller.dart';
import '../../data/app_update_installer.dart';
import '../../core/localization/app_strings.dart';
import '../../data/app_update_service.dart';
import '../../data/cloud_sync_service.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';
import '../add_flight/flight_import_actions.dart';
import 'feedback_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.controller,
    this.isActive = false,
    this.isHomeActive = false,
    this.updateService,
  });
  final AppController controller;
  final bool isActive;
  final bool isHomeActive;
  final AppUpdateService? updateService;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with FlightImportActions<ProfilePage> {
  static const _wideLayoutBreakpoint = 700.0;
  static const _sectionGap = 18.0;

  @override
  AppController get controller => widget.controller;
  bool get _canPromptForUpdates => widget.isActive || widget.isHomeActive;

  bool _isCheckingForUpdates = false;
  bool _hasCheckedForUpdatesAutomatically = false;
  bool _hasScheduledAutomaticUpdateCheck = false;
  String? _promptedUpdateVersion;
  String? _appVersion;
  AppUpdateResult? _updateResult;
  late final AppUpdateService _updateService =
      widget.updateService ?? AppUpdateService();

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppVersion());
    if (_canPromptForUpdates) _scheduleAutomaticUpdateCheck();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final version = packageInfo.version.trim();
      if (version.isEmpty) return;
      setState(() {
        _appVersion = version;
      });
    } catch (_) {
      // Keep the About page usable on platforms without package metadata.
    }
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_canPromptForUpdates &&
        !(oldWidget.isActive || oldWidget.isHomeActive)) {
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
      _hasScheduledAutomaticUpdateCheck = false;
      if (!mounted ||
          !_canPromptForUpdates ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _hasCheckedForUpdatesAutomatically = true;
      unawaited(_checkForUpdates(context, automatic: true));
    });
  }

  @override
  void dispose() {
    if (widget.updateService == null) _updateService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppSpacing.bottomBarClearance(context);
    return SafeArea(
      top: false,
      bottom: false,
      left: false,
      right: false,
      child: CustomScrollView(
        slivers: [
          if (importProgressNotice case final notice?)
            SliverToBoxAdapter(child: notice),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              bottomPadding,
            ),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final localData = _localDataCard(context);
                final settings = _settingsSection(context);
                final about = _aboutSection(context);
                final isDesktopPlatform =
                    Platform.isMacOS || Platform.isWindows || Platform.isLinux;
                // Foldables in portrait have a wide logical viewport but
                // still need a single iOS-style settings column. Reserve the
                // two-column layout for desktop and landscape surfaces.
                final isWide =
                    constraints.crossAxisExtent >= _wideLayoutBreakpoint &&
                    (isDesktopPlatform ||
                        constraints.crossAxisExtent >
                            constraints.viewportMainAxisExtent);
                final isDesktop = isWide && isDesktopPlatform;
                final dataManagement = _dataManagementSection(
                  context,
                  desktop: isDesktop,
                );

                if (isWide) {
                  return SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              localData,
                              const SizedBox(height: _sectionGap),
                              dataManagement,
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.cardGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              settings,
                              const SizedBox(height: _sectionGap),
                              about,
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return SliverList.list(
                  children: [
                    localData,
                    const SizedBox(height: _sectionGap),
                    dataManagement,
                    const SizedBox(height: _sectionGap),
                    settings,
                    const SizedBox(height: _sectionGap),
                    about,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _localDataCard(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final entryIconColor = isLight ? colors.displaySecondary : colors.lime;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: ShapeDecoration(
        color: colors.cardSurface,
        shape: AppShapes.large,
        shadows: _cardShadow(),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: colors.textPrimary),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: entryIconColor.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.phone_android_rounded, color: entryIconColor),
            ),
            const SizedBox(width: 14),
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
              style: TextStyle(
                color: colors.lime,
                fontSize: 40,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataManagementSection(BuildContext context, {bool desktop = false}) {
    final s = context.strings;
    final colors = context.appColors;
    final textColor = _profileTextColor(context);
    final secondaryTextColor = _profileSecondaryTextColor(context);
    if (desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: ShapeDecoration(
              color: colors.cardSurface,
              shape: AppShapes.large,
              shadows: _cardShadow(),
            ),
            child: Column(
              children: [
                _ProfileActionTile(
                  title: s.t('exportBackup'),
                  subtitle: 'JSON',
                  icon: Icons.ios_share_rounded,
                  color: colors.lime,
                  backgroundColor: colors.cardSurface,
                  textColor: textColor,
                  secondaryTextColor: secondaryTextColor,
                  wide: true,
                  onTap: () => _export(context),
                ),
                const SizedBox(height: 8),
                _ProfileActionTile(
                  title: s.t('importWebData'),
                  subtitle: 'JSON',
                  icon: Icons.file_download_outlined,
                  color: colors.purple,
                  backgroundColor: colors.cardSurface,
                  textColor: textColor,
                  secondaryTextColor: secondaryTextColor,
                  wide: true,
                  onTap: () => _import(context),
                ),
                const SizedBox(height: 8),
                _ProfileActionTile(
                  title: s.t('importExcel'),
                  subtitle: '.xlsx / .xls / .csv',
                  icon: Icons.table_view_rounded,
                  color: colors.purple,
                  backgroundColor: colors.cardSurface,
                  textColor: textColor,
                  secondaryTextColor: secondaryTextColor,
                  wide: true,
                  onTap: isImporting ? null : () => importSpreadsheet(context),
                ),
                const SizedBox(height: 8),
                _ProfileActionTile(
                  title: s.t('importCalendar'),
                  subtitle: '系统日历',
                  icon: Icons.calendar_month_rounded,
                  color: colors.purple,
                  backgroundColor: colors.cardSurface,
                  textColor: textColor,
                  secondaryTextColor: secondaryTextColor,
                  wide: true,
                  onTap: isImporting ? null : () => importCalendar(context),
                ),
                const SizedBox(height: 8),
                _cloudSyncTile(
                  context,
                  title: s.t('cloudSync'),
                  textColor: textColor,
                  secondaryTextColor: secondaryTextColor,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileGroup(
          children: [
            _ProfileActionTile(
              title: s.t('importExcel'),
              subtitle: '.xlsx / .xls / .csv',
              icon: Icons.table_view_rounded,
              color: colors.purple,
              backgroundColor: Colors.transparent,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              wide: true,
              onTap: isImporting ? null : () => importSpreadsheet(context),
            ),
            const _ProfileGroupDivider(),
            _ProfileActionTile(
              title: s.t('importWebData'),
              subtitle: 'JSON',
              icon: Icons.file_download_outlined,
              color: colors.purple,
              backgroundColor: Colors.transparent,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              wide: true,
              onTap: () => _import(context),
            ),
            const _ProfileGroupDivider(),
            _ProfileActionTile(
              title: s.t('importCalendar'),
              subtitle: '系统日历',
              icon: Icons.calendar_month_rounded,
              color: colors.purple,
              backgroundColor: Colors.transparent,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              wide: true,
              onTap: isImporting ? null : () => importCalendar(context),
            ),
            const _ProfileGroupDivider(),
            _ProfileActionTile(
              title: s.t('exportBackup'),
              subtitle: 'JSON',
              icon: Icons.ios_share_rounded,
              color: colors.lime,
              backgroundColor: Colors.transparent,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              wide: true,
              onTap: () => _export(context),
            ),
            const _ProfileGroupDivider(),
            _cloudSyncTile(
              context,
              title: s.t('cloudSync'),
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              grouped: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _cloudSyncTile(
    BuildContext context, {
    required String title,
    required Color textColor,
    required Color secondaryTextColor,
    bool grouped = false,
  }) {
    final s = context.strings;
    final colors = context.appColors;
    return ListenableBuilder(
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
        final isLight = Theme.of(context).brightness == Brightness.light;
        return _ProfileActionTile(
          title: title,
          value: value,
          icon: isConfigured ? Icons.cloud_done_outlined : Icons.cloud_outlined,
          color: isConfigured
              ? (isLight ? textColor : colors.lime)
              : colors.textTertiary,
          backgroundColor: grouped ? Colors.transparent : colors.cardSurface,
          textColor: isConfigured ? textColor : colors.textPrimary,
          secondaryTextColor: isConfigured
              ? secondaryTextColor
              : colors.textSecondary,
          wide: true,
          onTap: () => _openCloudSync(context),
        );
      },
    );
  }

  Widget _settingsSection(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    final textColor = _profileTextColor(context);
    final secondaryColor = colors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileGroup(
          children: [
            _ProfileActionTile(
              title: s.t('theme'),
              value: switch (controller.themeMode) {
                ThemeMode.system => s.t('themeSystem'),
                ThemeMode.light => s.t('themeLight'),
                ThemeMode.dark => s.t('themeDark'),
              },
              icon: Icons.brightness_6_rounded,
              color: colors.purple,
              backgroundColor: Colors.transparent,
              textColor: textColor,
              secondaryTextColor: secondaryColor,
              wide: true,
              onTap: () => _theme(context),
            ),
            const _ProfileGroupDivider(),
            _ProfileActionTile(
              title: s.t('language'),
              value: controller.locale.languageCode == 'zh'
                  ? s.t('chinese')
                  : s.t('english'),
              icon: Icons.translate_rounded,
              color: colors.purple,
              backgroundColor: Colors.transparent,
              textColor: textColor,
              secondaryTextColor: secondaryColor,
              wide: true,
              onTap: () => _language(context),
            ),
            const _ProfileGroupDivider(),
            _ProfileActionTile(
              title: s.t('travellerName'),
              value: controller.travellerName == 'TRAVELER'
                  ? s.t('travellerNameEmpty')
                  : controller.travellerName,
              icon: Icons.badge_outlined,
              color: colors.lime,
              backgroundColor: Colors.transparent,
              textColor: textColor,
              secondaryTextColor: secondaryColor,
              wide: true,
              onTap: () => _editTravellerName(context),
            ),
            const _ProfileGroupDivider(),
            _ProfileActionTile(
              title: s.t('feedbackTitle'),
              subtitle: s.t('feedbackEntryHint'),
              icon: Icons.chat_bubble_outline_rounded,
              color: colors.lime,
              backgroundColor: Colors.transparent,
              textColor: textColor,
              secondaryTextColor: secondaryColor,
              wide: true,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const FeedbackPage()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _aboutSection(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = _profileTextColor(context);
    final aboutCardColor = colors.cardSurface;
    final aboutIconColor = isLight ? colors.displaySecondary : colors.lime;
    final aboutPrimaryButtonBackground = colors.actionFill;
    final aboutPrimaryButtonForeground = colors.onPrimary;
    final aboutSecondaryButtonBackground = isLight
        ? Color.lerp(Colors.white, colors.displaySecondary, .20)!
        : colors.surfaceElevated;
    final aboutSecondaryButtonForeground = isLight
        ? Color.lerp(colors.displaySecondary, textColor, .30)!
        : colors.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          padding: EdgeInsets.zero,
          color: aboutCardColor,
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
                        color: aboutIconColor.withValues(
                          alpha: isLight ? .16 : .14,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.flight_takeoff_rounded,
                        color: aboutIconColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Flight Footprint',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${s.t('version')} ${_appVersion ?? '…'}',
                            style: AppTextStyles.label.copyWith(
                              color: colors.purple,
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
                        backgroundColor: aboutPrimaryButtonBackground,
                        foregroundColor: aboutPrimaryButtonForeground,
                        onPressed: () => _checkForUpdates(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ProfileAboutButton(
                        title: s.t('githubProject'),
                        icon: Icons.code_rounded,
                        backgroundColor: aboutSecondaryButtonBackground,
                        foregroundColor: aboutSecondaryButtonForeground,
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
            ],
          ),
        ),
      ],
    );
  }

  Color _profileTextColor(BuildContext context) {
    final colors = context.appColors;
    return colors.textPrimary;
  }

  Color _profileSecondaryTextColor(BuildContext context) {
    final colors = context.appColors;
    return colors.textSecondary;
  }

  List<BoxShadow> _cardShadow() => AppShadows.card(context);

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
      // This state also owns the home startup check while offstage. Prompt
      // only on home/About, never over another tab or a pushed route/sheet.
      // The next eligible visit may retry a result that was not presented.
      if (!_canPromptForUpdates || ModalRoute.of(context)?.isCurrent != true) {
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
        await _showUpdatePrompt(context, result, force: true);
      case UpdateCheckStatus.upToDate:
        await _showReleaseNotes(context, result);
      case UpdateCheckStatus.notConfigured:
        _message(context, strings.t('githubProjectNotConfigured'));
      case UpdateCheckStatus.unavailable:
        _message(context, strings.t('updateCheckFailed'));
    }
  }

  Future<void> _showUpdatePrompt(
    BuildContext context,
    AppUpdateResult result, {
    bool force = false,
  }) async {
    final latestVersion = result.latestVersion;
    if (latestVersion == null ||
        (!force && _promptedUpdateVersion == latestVersion)) {
      return;
    }
    if (!force) _promptedUpdateVersion = latestVersion;

    final strings = context.strings;
    final colors = context.appColors;
    final currentVersion = result.currentVersion ?? '—';
    final releaseNotes = result.releaseNotes?.trim();
    final canInstallInApp =
        result.canDownloadInApp && AppUpdateInstaller.isSupported;
    final shouldOpen = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (dialogContext) => Dialog(
        backgroundColor: colors.surfaceElevated,
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
                  color: colors.lime.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.system_update_alt_rounded,
                  color: colors.lime,
                  size: 26,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                strings.t('updateAvailable'),
                style: AppTextStyles.sectionTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${strings.t('currentVersionLabel')}  v$currentVersion',
                style: AppTextStyles.bodySecondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${strings.t('latestVersionLabel')}  v$latestVersion',
                style: AppTextStyles.body.copyWith(
                  color: colors.lime,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  strings.t('releaseNotes'),
                  style: AppTextStyles.label.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _ReleaseNotesPanel(notes: releaseNotes),
              ],
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
                      backgroundColor: colors.actionFill,
                      foregroundColor: colors.onPrimary,
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

  Future<void> _showReleaseNotes(
    BuildContext context,
    AppUpdateResult result,
  ) async {
    final strings = context.strings;
    final colors = context.appColors;
    final releaseNotes = result.releaseNotes?.trim();
    final shouldOpenRelease = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (dialogContext) => Dialog(
        backgroundColor: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: AppShapes.large,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colors.purple.withValues(alpha: .18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.history_rounded, color: colors.purple),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      strings.t('releaseNotes'),
                      style: AppTextStyles.sectionTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${strings.t('version')}  v${result.latestVersion ?? result.currentVersion ?? '—'} · ${strings.t('upToDate')}',
                style: AppTextStyles.bodySecondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              if (releaseNotes != null && releaseNotes.isNotEmpty)
                _ReleaseNotesPanel(notes: releaseNotes)
              else
                Text(
                  strings.t('noReleaseNotes'),
                  style: AppTextStyles.bodySecondary.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(strings.t('close')),
                  ),
                  if (result.releaseUrl != null) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.purple,
                        foregroundColor: Colors.white,
                        shape: AppShapes.pill,
                      ),
                      child: Text(strings.t('openRelease')),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (shouldOpenRelease == true &&
        result.releaseUrl != null &&
        context.mounted) {
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
    var installerDownloaded = false;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: context.appColors.background.withValues(alpha: .86),
      builder: (_) => _UpdateDownloadDialog(progress: progress),
    );

    try {
      // Give the progress surface one frame to appear before network I/O.
      await WidgetsBinding.instance.endOfFrame;
      final installer = await _updateService.downloadArtifact(
        result,
        onProgress: (received, total) {
          progress.value = total == null || total <= 0
              ? null
              : (received / total).clamp(0.0, 1.0).toDouble();
        },
      );
      installerDownloaded = true;
      if (context.mounted && dialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogVisible = false;
      }
      if (context.mounted) await dialogFuture;
      if (!context.mounted) return;
      await AppUpdateInstaller.install(installer);
    } catch (error) {
      if (context.mounted && dialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogVisible = false;
        await dialogFuture;
      }
      if (context.mounted) {
        final message = installerDownloaded
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

  void _language(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(context.strings.t('chinese')),
                trailing: controller.locale.languageCode == 'zh'
                    ? Icon(Icons.check_circle, color: context.appColors.lime)
                    : null,
                onTap: () async {
                  await controller.setLocale(const Locale('zh'));
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(context.strings.t('english')),
                trailing: controller.locale.languageCode == 'en'
                    ? Icon(Icons.check_circle, color: context.appColors.lime)
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

  void _theme(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      showDragHandle: true,
      shape: AppShapes.sheet,
      builder: (sheetContext) {
        final s = sheetContext.strings;
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ThemeOption(
                  title: s.t('themeSystem'),
                  icon: Icons.brightness_auto_rounded,
                  selected: controller.themeMode == ThemeMode.system,
                  onTap: () async {
                    await controller.setThemeMode(ThemeMode.system);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
                _ThemeOption(
                  title: s.t('themeLight'),
                  icon: Icons.light_mode_rounded,
                  accentColor: isDark
                      ? AppThemeColors.light.displayPrimary
                      : AppThemeColors.light.lime,
                  selected: controller.themeMode == ThemeMode.light,
                  onTap: () async {
                    await controller.setThemeMode(ThemeMode.light);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
                _ThemeOption(
                  title: s.t('themeDark'),
                  icon: Icons.dark_mode_rounded,
                  accentColor: isDark
                      ? AppThemeColors.dark.lime
                      : Color.lerp(
                          AppThemeColors.dark.lime,
                          AppThemeColors.dark.background,
                          .5,
                        ),
                  selected: controller.themeMode == ThemeMode.dark,
                  onTap: () async {
                    await controller.setThemeMode(ThemeMode.dark);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        );
      },
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
      backgroundColor: context.appColors.surface,
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

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.accentColor,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = accentColor ?? colors.textSecondary;
    return ListTile(
      shape: AppShapes.medium,
      leading: Icon(icon, color: accent),
      title: Text(
        title,
        style: TextStyle(
          color: accentColor ?? colors.textPrimary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: accentColor ?? colors.lime)
          : null,
      onTap: onTap,
    );
  }
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
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final inputFill = isLight
        ? Color.alphaBlend(
            colors.cardBlue.withValues(alpha: .78),
            colors.surface,
          )
        : colors.surfaceElevated;
    const pillInputBorder = OutlineInputBorder(
      borderRadius: AppRadii.pill,
      borderSide: BorderSide.none,
    );
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t('enterTravellerName'),
              style: AppTextStyles.sectionTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.t('travellerNameHint'),
              style: AppTextStyles.bodySecondary.copyWith(
                color: colors.textSecondary,
              ),
            ),
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
                fillColor: inputFill,
                prefixIconColor: colors.textSecondary,
                border: pillInputBorder,
                enabledBorder: pillInputBorder,
                focusedBorder: pillInputBorder,
                disabledBorder: pillInputBorder,
                counterStyle: TextStyle(color: colors.textSecondary),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _cancel,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: isLight
                          ? colors.cardLavender
                          : colors.surfaceElevated,
                      foregroundColor: colors.cardText,
                      shape: AppShapes.large,
                      side: BorderSide.none,
                    ),
                    child: Text(s.t('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: colors.actionFill,
                      foregroundColor: colors.onPrimary,
                      shape: AppShapes.large,
                      side: BorderSide.none,
                    ),
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

class _ProfileGroup extends StatelessWidget {
  const _ProfileGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final surface = context.appColors.cardSurface;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: surface,
      borderRadius: AppRadii.medium,
      showBorder: false,
      boxShadow: _profileGroupShadow(context),
      child: Column(children: children),
    );
  }
}

class _ProfileGroupDivider extends StatelessWidget {
  const _ProfileGroupDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: .7,
    indent: 70,
    endIndent: 16,
    color: context.appColors.border.withValues(alpha: .56),
  );
}

List<BoxShadow> _profileGroupShadow(BuildContext context) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  if (isLight) return const <BoxShadow>[];
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: .14),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
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
    final colors = context.appColors;
    final enabled = onPressed != null;
    final primaryColor = enabled ? foregroundColor : colors.textSecondary;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: colors.surface,
          disabledForegroundColor: colors.textTertiary,
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
    final colors = context.appColors;
    return Dialog(
      backgroundColor: colors.surfaceElevated,
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
              Icon(Icons.downloading_rounded, color: colors.lime, size: 30),
              const SizedBox(height: 16),
              Text(
                strings.t('downloadingUpdate'),
                style: AppTextStyles.sectionTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: value,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99),
                color: colors.lime,
                backgroundColor: colors.lime.withValues(alpha: .14),
              ),
              const SizedBox(height: 10),
              Text(
                value == null
                    ? strings.t('preparingUpdate')
                    : '${(value * 100).round()}%',
                style: AppTextStyles.label.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReleaseNotesPanel extends StatelessWidget {
  const _ReleaseNotesPanel({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 150),
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: ShapeDecoration(
            color: colors.background.withValues(alpha: .58),
            shape: AppShapes.small,
          ),
          child: Text(
            notes,
            style: AppTextStyles.bodySecondary.copyWith(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
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
    this.textColor,
    this.secondaryTextColor,
    this.wide = false,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color? textColor;
  final Color? secondaryTextColor;
  final VoidCallback? onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final iconColor = isLight ? colors.displaySecondary : color;
    final resolvedTextColor = textColor ?? colors.textPrimary;
    final resolvedSecondaryTextColor =
        secondaryTextColor ?? colors.textSecondary;
    final label = [title, ?subtitle, ?value].join(' ');
    final content = wide
        ? Row(
            children: [
              _IconTile(icon: icon, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body.copyWith(
                        color: resolvedTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.label.copyWith(
                          color: resolvedSecondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
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
                      color: resolvedSecondaryTextColor,
                    ),
                  ),
                ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [_IconTile(icon: icon, color: iconColor)],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  color: resolvedTextColor,
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
                    color: resolvedSecondaryTextColor,
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
        constraints: BoxConstraints(minHeight: wide ? 72 : 116),
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: AppShapes.medium,
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: AppShapes.medium,
          child: Padding(padding: const EdgeInsets.all(14), child: content),
        ),
      ),
    );
  }
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
        final colors = context.appColors;
        final insets = MediaQuery.viewInsetsOf(context);
        return Material(
          color: colors.background,
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
                          color: colors.lime.withValues(alpha: .14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.cloud_outlined,
                          color: colors.lime,
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
                          style: TextStyle(color: colors.danger),
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
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.danger,
            ),
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
    final colors = context.appColors;
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
                floatingLabelBehavior: FloatingLabelBehavior.always,
                filled: true,
                fillColor: colors.surfaceElevated,
                contentPadding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
                labelStyle: AppTextStyles.label.copyWith(
                  color: colors.textSecondary,
                ),
                floatingLabelStyle: TextStyle(
                  color: colors.lime,
                  backgroundColor: colors.surfaceElevated,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
                hintStyle: AppTextStyles.bodySecondary.copyWith(
                  color: colors.textTertiary,
                  fontSize: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.medium,
                  gapPadding: 8,
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.medium,
                  gapPadding: 8,
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadii.medium,
                  gapPadding: 8,
                  borderSide: BorderSide(color: colors.lime, width: 1.5),
                ),
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
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: dialogContext.appColors.textPrimary,
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
    final colors = context.appColors;
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
        color: colors.surfaceElevated,
        shape: AppShapes.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: colors.lime),
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
                foregroundColor: colors.lime,
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
              style: TextStyle(color: colors.danger, fontSize: 13),
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 50),
          backgroundColor: colors.surfaceElevated,
          foregroundColor: colors.textPrimary,
          disabledBackgroundColor: colors.surface,
          disabledForegroundColor: colors.textTertiary,
          shape: AppShapes.large,
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autocorrect: false,
      textCapitalization: textCapitalization,
      style: AppTextStyles.body.copyWith(color: colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintMaxLines: 2,
        filled: true,
        fillColor: colors.surfaceElevated,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: colors.textTertiary),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
        labelStyle: AppTextStyles.label.copyWith(color: colors.textSecondary),
        floatingLabelStyle: TextStyle(
          color: colors.lime,
          backgroundColor: colors.surfaceElevated,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
        hintStyle: AppTextStyles.bodySecondary.copyWith(
          color: colors.textTertiary,
          fontSize: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.medium,
          gapPadding: 8,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.medium,
          gapPadding: 8,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.medium,
          gapPadding: 8,
          borderSide: BorderSide(color: colors.lime, width: 1.5),
        ),
      ),
    );
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: colors.lime.withValues(alpha: .08),
        shape: AppShapes.medium,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: colors.lime, size: 20),
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
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: colors.danger.withValues(alpha: .1),
        shape: RoundedSuperellipseBorder(
          borderRadius: AppRadii.small,
          side: BorderSide(color: colors.danger.withValues(alpha: .32)),
        ),
      ),
      child: Text(text, style: TextStyle(color: colors.danger)),
    );
  }
}

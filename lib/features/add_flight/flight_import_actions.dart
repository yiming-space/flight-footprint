import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../data/airport_localization.dart';
import '../../data/calendar_import_service.dart';
import '../../data/flight_repository.dart';
import '../../data/flight_draft_store.dart';
import '../../data/flight_spreadsheet_import_service.dart';
import '../../data/flight_time_resolver.dart';
import '../../data/screenshot_flight_recognizer.dart';
import '../../domain/flight.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/widgets.dart';
import 'add_flight_page.dart';

/// Shared review, conflict handling and import UI for the entry sheet and Profile.
/// No records are written until the existing preview has been confirmed.
mixin FlightImportActions<T extends StatefulWidget> on State<T> {
  AppController get controller;

  bool _isRecognizingSpreadsheet = false;
  bool _isReadingCalendar = false;
  bool _isRecognizingScreenshot = false;
  bool isImporting = false;
  String? importErrorMessage;

  Widget? get importProgressNotice => _isRecognizingSpreadsheet
      ? const _SpreadsheetRecognizingNotice()
      : _isReadingCalendar
      ? const _CalendarReadingNotice()
      : _isRecognizingScreenshot
      ? Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            context.strings.isZh ? '正在识别截图…' : 'Recognizing screenshot…',
          ),
        )
      : null;

  Future<bool> importSpreadsheet(BuildContext context) =>
      _runImport(context, () => _runSpreadsheetImport(context));

  Future<bool> importCalendar(BuildContext context) =>
      _runImport(context, () => _runCalendarImport(context));

  Future<bool> importScreenshot(BuildContext context) =>
      _runImport(context, () => _runScreenshotImport(context));

  Future<bool> _runScreenshotImport(BuildContext context) async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || !context.mounted) return false;
    final items = <({FlightDraft draft, Uint8List image})>[];
    final images = <Uint8List>[];
    final identities = <String>{};
    var skipped = 0;
    setState(() => _isRecognizingScreenshot = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      for (final file in picked) {
        Uint8List bytes;
        try {
          bytes = await file.readAsBytes();
        } catch (_) {
          skipped++;
          continue;
        }
        if (!context.mounted) return false;
        if (bytes.length > 20 * 1024 * 1024 ||
            images.any((image) => listEquals(image, bytes))) {
          skipped++;
          continue;
        }
        images.add(bytes);
        List<String> lines;
        try {
          lines = await const ScreenshotFlightRecognizer().recognize(bytes);
        } on PlatformException catch (error) {
          if (error.code == 'unsupported') rethrow;
          skipped++;
          continue;
        }
        for (final draft in parseScreenshotFlights(
          lines,
          controller.airports,
        )) {
          if (!draft.hasMeaningfulContent) {
            skipped++;
            continue;
          }
          final key =
              draft.identity.isNotEmpty &&
                  draft.departureIata != null &&
                  draft.arrivalIata != null &&
                  draft.dateTouched
              ? '${draft.identity}|${draft.departureIata}|${draft.arrivalIata}|${draft.date!.toIso8601String()}'
              : null;
          if (key != null && !identities.add(key)) {
            skipped++;
            continue;
          }
          items.add((draft: draft, image: bytes));
        }
      }
    } on MissingPluginException {
      if (context.mounted)
        _message(
          context,
          context.strings.isZh
              ? '当前平台暂不支持截图识别'
              : 'Screenshot recognition is not available on this platform',
        );
      return false;
    } on PlatformException catch (error) {
      if (context.mounted)
        _message(
          context,
          error.code == 'unsupported'
              ? (context.strings.isZh
                    ? '截图识别需要 Android 8.0 或更高版本'
                    : 'Screenshot recognition requires Android 8.0 or later')
              : (context.strings.isZh
                    ? '识别失败，请更换截图重试'
                    : 'Recognition failed. Please try another image.'),
        );
      return false;
    } finally {
      if (mounted) setState(() => _isRecognizingScreenshot = false);
    }
    if (!context.mounted) return false;
    if (items.isEmpty) {
      _message(
        context,
        context.strings.isZh ? '未识别到航班信息，请更换截图或手动录入' : 'No flight information found. Try another image or enter it manually.',
      );
      return false;
    }
    final selected = <int>{for (var i = 0; i < items.length; i++) i};
    if (items.length > 1 || skipped > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, refresh) => AlertDialog(
            title: Text(
              dialogContext.strings.isZh
                  ? '截图航班预览'
                  : 'Screenshot flight preview',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (skipped > 0)
                    Text(
                      dialogContext.strings.isZh
                          ? '跳过 $skipped 个重复、过大或识别失败的项目'
                          : 'Skipped $skipped duplicate, oversized or unrecognized items',
                    ),
                  for (var i = 0; i < items.length; i++)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${items[i].draft.identity.isEmpty ? '—' : items[i].draft.identity}  ${items[i].draft.departureIata ?? '?'} → ${items[i].draft.arrivalIata ?? '?'}',
                      ),
                      value: selected.contains(i),
                      onChanged: (value) => refresh(() {
                        if (value == true) {
                          selected.add(i);
                        } else {
                          selected.remove(i);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(dialogContext.strings.t('cancel')),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(
                  dialogContext.strings.isZh ? '依次核对' : 'Review flights',
                ),
              ),
            ],
          ),
        ),
      );
      if (proceed != true || !context.mounted) return false;
    }
    final addedRecords = <Flight>[];
    for (var index = 0; index < items.length; index++) {
      if (!selected.contains(index)) continue;
      final item = items[index];
      if (!context.mounted) break;
      final saved = await showModalBottomSheet<Flight>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        requestFocus: false,
        backgroundColor: Colors.transparent,
        builder: (_) => FractionallySizedBox(
          heightFactor: .94,
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: AppShapes.sheet),
            child: AddFlightPage(
              controller: controller,
              initialScreenshotDraft: item.draft,
              screenshotImage: item.image,
            ),
          ),
        ),
      );
      if (saved != null) addedRecords.add(saved);
    }
    if (context.mounted && addedRecords.isNotEmpty) {
      await _showUndoAdded(context, addedRecords);
    }
    return addedRecords.isNotEmpty;
  }

  Future<void> _showUndoAdded(
    BuildContext context,
    List<Flight> flights,
  ) async {
    final shouldUndo = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.strings.isZh ? '导入完成' : 'Import complete'),
        content: Text(
          dialogContext.strings.isZh
              ? '新增 ${flights.length} 条航程。可撤销本次新增，已修改的记录会保留。'
              : 'Added ${flights.length} flights. You can undo unchanged additions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.strings.isZh ? '撤销新增' : 'Undo additions'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.strings.t('close')),
          ),
        ],
      ),
    );
    if (shouldUndo != true || !context.mounted) return;
    final removed = await controller.undoAddedFlights(flights);
    if (context.mounted)
      _message(
        context,
        context.strings.isZh
            ? '已撤销 $removed 条新增航程'
            : 'Undid $removed additions',
      );
  }

  Future<bool> _runImport(
    BuildContext context,
    Future<bool> Function() operation,
  ) async {
    if (isImporting) return false;
    setState(() {
      isImporting = true;
      importErrorMessage = null;
    });
    try {
      return await operation();
    } catch (error) {
      if (context.mounted) {
        _message(context, '${context.strings.t('operationFailed')}: $error');
      }
      return false;
    } finally {
      if (mounted) setState(() => isImporting = false);
    }
  }

  void _message(BuildContext context, String message) {
    if (mounted) setState(() => importErrorMessage = message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _runSpreadsheetImport(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );
      if (picked == null) return false;
      final bytes = await picked.readAsBytes();
      if (!context.mounted) return false;
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
      if (!context.mounted) return false;
      if (!parsed.hasRows) {
        _message(context, context.strings.t('spreadsheetNoRows'));
        return false;
      }
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SpreadsheetPreviewSheet(
          result: parsed,
          preview: preview,
          timeZoneForIata: controller.airports.timeZoneIdForIata,
        ),
      );
      if (confirmed != true || !context.mounted) return false;
      var overwriteExisting = false;
      if (preview.summary.conflicts > 0) {
        final decision = await _confirmSpreadsheetOverwrite(
          context,
          preview.summary.conflicts,
        );
        if (decision == null || !context.mounted) return false;
        overwriteExisting = decision;
      }

      final progress = ValueNotifier<double?>(0);
      final progressDialog = showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: context.appColors.background,
        builder: (_) => PopScope(
          canPop: false,
          child: _SpreadsheetProgressDialog(progress: progress),
        ),
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
      if (!context.mounted) return false;
      await _showSpreadsheetComplete(context, imported, parsed.issues);
      return true;
    } catch (error) {
      if (context.mounted) {
        _message(context, '${context.strings.t('operationFailed')}: $error');
      }
      return false;
    }
  }

  Future<bool> _runCalendarImport(BuildContext context) async {
    if (_isReadingCalendar) return false;
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

    if (!context.mounted) return false;
    return _reviewCalendarScan(context, scanned);
  }

  Future<bool> _reviewCalendarScan(
    BuildContext context,
    CalendarImportResult scanned,
  ) async {
    switch (scanned.status) {
      case CalendarScanStatus.permissionDenied:
        _message(context, context.strings.t('calendarPermissionDenied'));
        return false;
      case CalendarScanStatus.unsupported:
        _message(context, context.strings.t('calendarUnsupported'));
        return false;
      case CalendarScanStatus.failed:
        _message(
          context,
          '${context.strings.t('operationFailed')}: ${scanned.errorCode ?? 'calendar'}',
        );
        return false;
      case CalendarScanStatus.available:
        break;
    }
    if (scanned.flights.isEmpty) {
      if (scanned.reviewCandidates > 0) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogContext.strings.t('calendarImportTitle')),
            content: Text(
              dialogContext.strings
                      .t('calendarNeedsReview')
                      .replaceFirst('{count}', '${scanned.reviewCandidates}') +
                  (scanned.reviewTitles.isEmpty
                      ? ''
                      : '\n\n${scanned.reviewTitles.take(5).join('\n')}'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(dialogContext.strings.t('close')),
              ),
            ],
          ),
        );
      } else {
        _message(context, context.strings.t('calendarNoFlights'));
      }
      return false;
    }

    final selected = await showModalBottomSheet<List<CalendarFlightDraft>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CalendarPreviewSheet(result: scanned),
    );
    if (selected == null || !context.mounted) return false;
    if (selected.isEmpty) {
      _message(context, context.strings.t('calendarNoSelection'));
      return false;
    }

    final preview = await controller.previewCalendarFlights(selected);
    if (!context.mounted) return false;
    var overwriteExisting = false;
    if (preview.summary.conflicts > 0) {
      final decision = await _confirmSpreadsheetOverwrite(
        context,
        preview.summary.conflicts,
        preview: preview,
      );
      if (decision == null || !context.mounted) return false;
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
      return false;
    }
    if (!context.mounted) return false;
    await _showCalendarComplete(context, imported);
    if (context.mounted && imported.addedRecords.isNotEmpty)
      await _showUndoAdded(context, imported.addedRecords);
    return true;
  }

  Future<void> _showCalendarComplete(
    BuildContext context,
    FlightImportSummary summary,
  ) async {
    final s = context.strings;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.event_available_rounded,
          color: dialogContext.appColors.lime,
        ),
        title: Text(s.t('calendarImportDone')),
        content: _ImportCompletionBody(summary: summary, issueCount: 0),
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
    int conflictCount, {
    FlightImportPreview? preview,
  }) => showDialog<bool?>(
    context: context,
    builder: (dialogContext) {
      final s = context.strings;
      var message = s
          .t('spreadsheetOverwriteMessage')
          .replaceFirst('{count}', '$conflictCount');
      if (preview != null && preview.existingByIncomingId.isNotEmpty) {
        String describe(Flight flight) {
          final zone = controller.airports.timeZoneIdForIata(
            flight.departureIata,
          );
          final wall =
              FlightTimeResolver.toWallTime(flight.departedAt, zone) ??
              flight.departedAt.toLocal();
          final arrivalZone = controller.airports.timeZoneIdForIata(
            flight.arrivalIata,
          );
          final arrival = flight.arrivedAt == null
              ? null
              : FlightTimeResolver.toWallTime(flight.arrivedAt!, arrivalZone) ??
                    flight.arrivedAt!.toLocal();
          return '${flight.flightNumber ?? ''}  ${flight.departureIata} → ${flight.arrivalIata}\n${DateFormat('yyyy-MM-dd HH:mm').format(wall)} → ${arrival == null ? '—' : DateFormat('yyyy-MM-dd HH:mm').format(arrival)}';
        }

        message +=
            '\n\n${preview.conflictingFlights.where((flight) => preview.existingByIncomingId.containsKey(flight.id)).map((flight) {
              final old = preview.existingByIncomingId[flight.id]!;
              final changes = <String>[if (old.departureIata != flight.departureIata || old.arrivalIata != flight.arrivalIata) s.isZh ? '机场' : 'airports', if (old.departedAt != flight.departedAt) s.isZh ? '起飞时间' : 'departure time', if (old.arrivedAt != flight.arrivedAt) s.isZh ? '到达时间' : 'arrival time', if (old.flightNumber != flight.flightNumber) s.isZh ? '航班号' : 'flight number'];
              return '${changes.isEmpty ? '' : '${s.isZh ? '变更' : 'Changed'}：${changes.join('、')}\n'}${s.isZh ? '已有' : 'Existing'}: ${describe(old)}\n${s.isZh ? '日历' : 'Calendar'}: ${describe(flight)}';
            }).join('\n\n')}';
      }
      return AlertDialog(
        scrollable: true,
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
    List<SpreadsheetImportIssue> issues,
  ) async {
    final s = context.strings;
    final reviewIssues = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.check_circle_rounded,
          color: dialogContext.appColors.lime,
        ),
        title: Text(s.t('spreadsheetImportDone')),
        content: _ImportCompletionBody(
          summary: summary,
          issueCount: issues.length,
        ),
        actions: [
          if (issues.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(s.t('reviewImportIssues')),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.t('close')),
          ),
        ],
      ),
    );
    if (reviewIssues == true && context.mounted) {
      await _showSpreadsheetIssues(context, issues);
    }
    if (context.mounted && summary.addedRecords.isNotEmpty)
      await _showUndoAdded(context, summary.addedRecords);
  }

  Future<void> _showSpreadsheetIssues(
    BuildContext context,
    List<SpreadsheetImportIssue> issues,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: .72,
      child: Material(
        color: sheetContext.appColors.background,
        shape: AppShapes.sheet,
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sheetContext.strings.t('spreadsheetIssueRows'),
                        style: AppTextStyles.sectionTitle,
                      ),
                    ),
                    IconButton(
                      tooltip: sheetContext.strings.t('close'),
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: _SpreadsheetIssuesPanel(
                      issues: issues,
                      hint: sheetContext.strings.t('spreadsheetIssuesHint'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ImportCompletionBody extends StatelessWidget {
  const _ImportCompletionBody({
    required this.summary,
    required this.issueCount,
  });

  final FlightImportSummary summary;
  final int issueCount;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    final duplicates = summary.unchanged + summary.skipped;
    final followUp = issueCount == 0
        ? s.t('importCompleteClean')
        : s
              .t('importCompleteNeedsReview')
              .replaceFirst('{count}', '$issueCount');
    return SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final metricWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ImportResultMetric(
                    width: metricWidth,
                    label: s.t('importAdded'),
                    value: summary.added,
                    color: colors.lime,
                  ),
                  _ImportResultMetric(
                    width: metricWidth,
                    label: s.t('importUpdated'),
                    value: summary.updated,
                    color: colors.purple,
                  ),
                  _ImportResultMetric(
                    width: metricWidth,
                    label: s.t('importDuplicates'),
                    value: duplicates,
                    color: colors.cardBlue,
                  ),
                  _ImportResultMetric(
                    width: metricWidth,
                    label: s.t('importNeedsReview'),
                    value: issueCount,
                    color: issueCount == 0 ? colors.cardMint : colors.danger,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                issueCount == 0
                    ? Icons.task_alt_rounded
                    : Icons.info_outline_rounded,
                size: 19,
                color: issueCount == 0 ? colors.lime : colors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  followUp,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImportResultMetric extends StatelessWidget {
  const _ImportResultMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.color,
  });

  final double width;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      label: '$label, $value',
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: ShapeDecoration(
          color: Color.alphaBlend(color.withValues(alpha: .12), colors.surface),
          shape: AppShapes.small,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '$value ${context.strings.t('importResultUnit')}',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: ShapeDecoration(
          color: colors.surfaceElevated,
          shape: RoundedSuperellipseBorder(
            borderRadius: AppRadii.medium,
            side: BorderSide(color: colors.lime.withValues(alpha: .5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: colors.lime.withValues(alpha: .16),
                shape: AppShapes.small,
              ),
              child: Icon(
                Icons.table_chart_rounded,
                size: 18,
                color: colors.lime,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.strings.t('spreadsheetRecognizing'),
                style: AppTextStyles.body.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colors.lime,
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
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: ShapeDecoration(
          color: colors.surfaceElevated,
          shape: RoundedSuperellipseBorder(
            borderRadius: AppRadii.medium,
            side: BorderSide(color: colors.purple.withValues(alpha: .5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: colors.purple.withValues(alpha: .16),
                shape: AppShapes.small,
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: colors.purple,
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
              decoration: BoxDecoration(
                color: colors.purple,
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
    final colors = context.appColors;
    final allSelected = _selected.length == widget.result.flights.length;
    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: colors.background,
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
                if (widget.result.reviewCandidates > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: ShapeDecoration(
                      color: colors.surfaceElevated,
                      shape: AppShapes.small,
                    ),
                    child: Text(
                      '${s.t('calendarNeedsReview').replaceFirst('{count}', '${widget.result.reviewCandidates}')}'
                      '${widget.result.reviewTitles.isEmpty ? '' : '\n${widget.result.reviewTitles.take(3).join('\n')}'}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
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
                          .format(
                            FlightTimeResolver.toWallTime(
                                  draft.departedAt,
                                  draft.departureAirport.timeZoneId,
                                ) ??
                                draft.departedAt.toLocal(),
                          );
                      final arrivalDate = DateFormat('yyyy-MM-dd HH:mm').format(
                        FlightTimeResolver.toWallTime(
                              draft.arrivedAt,
                              draft.arrivalAirport.timeZoneId,
                            ) ??
                            draft.arrivedAt.toLocal(),
                      );
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
                                    ? colors.surface
                                    : colors.surfaceElevated,
                                shape: RoundedSuperellipseBorder(
                                  borderRadius: AppRadii.medium,
                                  side: BorderSide(
                                    color: selected
                                        ? colors.lime.withValues(alpha: .72)
                                        : colors.border,
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
                                                        ? colors.purple
                                                        : colors.lime,
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
                                            color: colors.purple,
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
                                    activeColor: colors.actionFill,
                                    checkColor: colors.onPrimary,
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
  const _SpreadsheetPreviewSheet({
    required this.result,
    required this.preview,
    required this.timeZoneForIata,
  });

  final String? Function(String) timeZoneForIata;

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
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: colors.background,
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
                        color: colors.lime.withValues(alpha: .14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.table_chart_outlined,
                        color: colors.lime,
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
                        color: isLight ? colors.cardMint : colors.lime,
                        selected: _selectedTab == 0,
                        onTap: () => setState(() => _selectedTab = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpreadsheetReviewTabButton(
                        label: s.t('spreadsheetIssueRows'),
                        count: result.issues.length,
                        color: isLight ? colors.cardCoral : colors.danger,
                        selected: _selectedTab == 1,
                        onTap: () => setState(() => _selectedTab = 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpreadsheetReviewTabButton(
                        label: s.t('spreadsheetConflicts'),
                        count: _conflictRows.length,
                        color: isLight ? colors.cardLavender : colors.purple,
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
                            final date = DateFormat('yyyy-MM-dd HH:mm').format(
                              FlightTimeResolver.toWallTime(
                                    flight.departedAt,
                                    widget.timeZoneForIata(
                                      flight.departureIata,
                                    ),
                                  ) ??
                                  flight.departedAt.toLocal(),
                            );
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
                                  ? colors.purple
                                  : flight.isUpcoming
                                  ? colors.purple
                                  : colors.lime,
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
            context.appColors.surfaceElevated,
          );
    final colors = context.appColors;
    // Unselected counts share the same cool gray-blue ink as the surrounding
    // secondary labels (for example, “已结束 103”), instead of inheriting the
    // tab accent and becoming visually inconsistent between cards.
    final selectedInk = Theme.of(context).brightness == Brightness.light
        ? colors.textPrimary
        : colors.onPrimary;
    final countColor = selected ? selectedInk : colors.textSecondary;
    final labelColor = selected ? selectedInk : colors.textSecondary;
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: ShapeDecoration(
            color: colors.danger.withValues(alpha: .08),
            shape: AppShapes.medium,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: colors.danger,
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
                              style: TextStyle(
                                color: colors.danger,
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
          style: AppTextStyles.label.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
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
    final colors = context.appColors;
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
          color: colors.surfaceElevated,
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
                  color: colors.purple,
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
                  color: colors.danger.withValues(alpha: .08),
                  shape: AppShapes.small,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: colors.danger,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ambiguousAirportMessage!,
                        style: AppTextStyles.label.copyWith(
                          color: colors.danger,
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.lime.withValues(alpha: .14),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flight_takeoff_rounded, color: colors.lime, size: 18),
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(vertical: 3),
                color: colors.border,
              ),
              Icon(Icons.flight_land_rounded, color: colors.purple, size: 18),
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
}

class _SpreadsheetAirportLine extends StatelessWidget {
  const _SpreadsheetAirportLine({required this.code, required this.name});

  final String code;
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: code.isEmpty ? '—' : code,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (name.trim().isNotEmpty)
            TextSpan(
              text: '  ${name.trim()}',
              style: AppTextStyles.bodySecondary.copyWith(
                color: colors.textSecondary,
              ),
            ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SpreadsheetMetaItem extends StatelessWidget {
  const _SpreadsheetMetaItem({
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final resolvedColor = color ?? colors.textSecondary;
    return Semantics(
      label: text,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: resolvedColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTextStyles.label.copyWith(
              color: resolvedColor,
              fontWeight: resolvedColor == colors.purple
                  ? FontWeight.w700
                  : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
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
          Icon(icon, size: 42, color: context.appColors.textTertiary),
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
    final colors = context.appColors;
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
          backgroundColor: colors.surface,
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
            side: BorderSide(color: colors.border),
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
                          color: colors.lime,
                          backgroundColor: colors.surfaceElevated,
                        ),
                        SizedBox(
                          width: 54,
                          height: 54,
                          child: CustomPaint(
                            painter: _SpreadsheetTablePainter(colors: colors),
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
                        color: colors.lime,
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
                      color: colors.textTertiary,
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
    final colors = context.appColors;
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
                      ? colors.lime.withValues(alpha: .48)
                      : colors.border,
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
                        ? colors.actionFill
                        : colors.surfaceElevated,
                    border: Border.all(
                      color: index <= activeIndex ? colors.lime : colors.border,
                    ),
                  ),
                  child: index < activeIndex
                      ? Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: colors.onPrimary,
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: index == activeIndex
                                ? colors.onPrimary
                                : colors.textTertiary,
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
                        ? colors.textSecondary
                        : colors.textTertiary,
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
  const _SpreadsheetTablePainter({required this.colors});

  final AppThemeColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = colors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final softInk = Paint()
      ..color = colors.textSecondary
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

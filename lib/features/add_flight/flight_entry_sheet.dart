import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';
import 'flight_import_actions.dart';

enum FlightEntryMethod { manual, spreadsheet, calendar }

enum FlightEntryResult { manual, imported }

/// The same choices appear in the add sheet and first-record empty states.
class FlightEntryOptions extends StatelessWidget {
  const FlightEntryOptions({
    super.key,
    required this.onSelected,
    this.enabled = true,
  });

  final ValueChanged<FlightEntryMethod> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('flight-entry-manual'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            backgroundColor: colors.actionFill,
            foregroundColor: colors.onPrimary,
          ),
          onPressed: enabled
              ? () => onSelected(FlightEntryMethod.manual)
              : null,
          icon: const Icon(Icons.add_rounded),
          label: Text(s.t('entryManual'), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 12),
        _ImportOption(
          method: FlightEntryMethod.spreadsheet,
          icon: Icons.table_view_outlined,
          title: s.t('entrySpreadsheet'),
          description: s.t('entrySpreadsheetHint'),
          onTap: enabled
              ? () => onSelected(FlightEntryMethod.spreadsheet)
              : null,
        ),
        Divider(height: 1, color: colors.border),
        _ImportOption(
          method: FlightEntryMethod.calendar,
          icon: Icons.calendar_month_outlined,
          title: s.t('entryCalendar'),
          description: s.t('entryCalendarHint'),
          onTap: enabled ? () => onSelected(FlightEntryMethod.calendar) : null,
        ),
      ],
    );
  }
}

class _ImportOption extends StatelessWidget {
  const _ImportOption({
    required this.method,
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  final FlightEntryMethod method;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListTile(
      key: ValueKey('flight-entry-${method.name}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      minLeadingWidth: 24,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colors.purple.withValues(alpha: .12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: colors.purple, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(description, style: TextStyle(color: colors.textSecondary)),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

class FlightFirstRecord extends StatelessWidget {
  const FlightFirstRecord({super.key, required this.onSelected});

  final ValueChanged<FlightEntryMethod> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        context.strings.t('entryFirstTitle'),
        style: AppTextStyles.sectionTitle.copyWith(
          color: context.appColors.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        context.strings.t('entryFirstHint'),
        style: AppTextStyles.body.copyWith(
          color: context.appColors.textSecondary,
        ),
      ),
      const SizedBox(height: 20),
      FlightEntryOptions(onSelected: onSelected),
    ],
  );
}

class FlightEntrySheet extends StatefulWidget {
  const FlightEntrySheet({
    super.key,
    required this.controller,
    this.initialMethod,
  });

  final AppController controller;
  final FlightEntryMethod? initialMethod;

  @override
  State<FlightEntrySheet> createState() => _FlightEntrySheetState();
}

class _FlightEntrySheetState extends State<FlightEntrySheet>
    with FlightImportActions<FlightEntrySheet> {
  @override
  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (widget.initialMethod case final method?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _select(method);
      });
    }
  }

  Future<void> _select(FlightEntryMethod method) async {
    if (isImporting) return;
    if (method == FlightEntryMethod.manual) {
      Navigator.pop(context, FlightEntryResult.manual);
      return;
    }
    final imported = method == FlightEntryMethod.spreadsheet
        ? await importSpreadsheet(context)
        : await importCalendar(context);
    if (imported && mounted) Navigator.pop(context, FlightEntryResult.imported);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return PopScope(
      canPop: !isImporting,
      child: Material(
        color: context.appColors.surface,
        shape: AppShapes.sheet,
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.appColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t('addFlight'),
                        style: AppTextStyles.sectionTitle,
                      ),
                    ),
                    IconButton(
                      tooltip: s.t('close'),
                      onPressed: isImporting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  s.t('entryChooseHint'),
                  style: AppTextStyles.body.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                if (isImporting) ...[
                  Semantics(
                    liveRegion: true,
                    child:
                        importProgressNotice ??
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: LinearProgressIndicator(
                            semanticsLabel: s.t('entryImportInProgress'),
                          ),
                        ),
                  ),
                ],
                if (importErrorMessage case final message?) ...[
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        message,
                        style: TextStyle(color: context.appColors.danger),
                      ),
                    ),
                  ),
                ],
                FlightEntryOptions(onSelected: _select, enabled: !isImporting),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

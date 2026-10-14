import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/localization/app_strings.dart';
import '../../data/feedback_service.dart';
import '../../ui/theme/app_theme.dart';

/// A native form. Only the explicit submit action can send data to the relay.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, this.service});

  final FeedbackService? service;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  late final _service = widget.service ?? FeedbackService();
  final Future<String> _environment = _loadEnvironment();
  FeedbackKind _kind = FeedbackKind.bug;
  bool _includeEnvironment = true;
  bool _consent = false;
  bool _sending = false;
  bool _allowPop = false;
  String? _errorKey;
  String? _payloadKey;
  String? _requestId;
  FeedbackReceipt? _receipt;

  static Future<String> _loadEnvironment() async {
    // Deliberately exclude device IDs, system logs and the user's records.
    try {
      final info = await PackageInfo.fromPlatform();
      return 'Flight Footprint ${info.version} (${info.buildNumber})\nPlatform: ${Platform.operatingSystem}';
    } catch (_) {
      return 'Flight Footprint\nPlatform: ${Platform.operatingSystem}';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_sending) return;
    final s = context.strings;
    final hasDraft = _title.text.isNotEmpty || _description.text.isNotEmpty;
    if (_receipt == null && hasDraft) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.t('feedbackDiscardTitle')),
          content: Text(s.t('feedbackDiscardHint')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('feedbackKeepEditing')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('feedbackDiscard')),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _submit() async {
    if (_sending || !_consent || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _errorKey = null;
    });
    final environment = _includeEnvironment ? await _environment : null;
    if (!mounted) return;
    final submission = FeedbackSubmission(
      title: _title.text.trim(),
      description: _description.text.trim(),
      kind: _kind,
      environment: environment,
    );
    // A retry of an unchanged draft uses the original idempotency key.
    final key =
        '${_kind.name}\u0000${submission.title}\u0000${submission.description}\u0000${environment ?? ''}';
    if (key != _payloadKey) {
      _payloadKey = key;
      _requestId = const Uuid().v4();
    }
    try {
      final receipt = await _service.submit(submission, requestId: _requestId!);
      if (mounted) setState(() => _receipt = receipt);
    } on FeedbackException catch (error) {
      if (mounted) {
        setState(
          () => _errorKey = switch (error.code) {
            FeedbackErrorCode.notConfigured => 'feedbackNotConfigured',
            FeedbackErrorCode.rateLimited => 'feedbackRateLimited',
            FeedbackErrorCode.unavailable => 'feedbackUnavailable',
            FeedbackErrorCode.pending => 'feedbackPending',
            _ => 'feedbackFailed',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final colors = context.appColors;
    final receipt = _receipt;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          surfaceTintColor: Colors.transparent,
          title: Text(s.t('feedbackTitle')),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _sending ? null : _close,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: receipt != null
                  ? _success(receipt)
                  : Form(
                      key: _form,
                      child: ListView(
                        padding: const EdgeInsets.all(AppSpacing.page),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: ShapeDecoration(
                              color: colors.surfaceElevated,
                              shape: const StadiumBorder(),
                            ),
                            child: Row(
                              children: [
                                for (final kind in FeedbackKind.values)
                                  Expanded(
                                    child: TextButton(
                                      onPressed: _sending
                                          ? null
                                          : () => setState(() => _kind = kind),
                                      style: TextButton.styleFrom(
                                        backgroundColor: _kind == kind
                                            ? colors.lime
                                            : Colors.transparent,
                                        foregroundColor: _kind == kind
                                            ? colors.onPrimary
                                            : colors.textSecondary,
                                        shape: const StadiumBorder(),
                                        minimumSize: const Size(0, 48),
                                      ),
                                      child: Text(
                                        s.t(
                                          kind == FeedbackKind.bug
                                              ? 'feedbackBug'
                                              : 'feedbackSuggestion',
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            s.t('feedbackSubject'),
                            style: AppTextStyles.label,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Semantics(
                            label: s.t('feedbackSubject'),
                            child: TextFormField(
                              controller: _title,
                              enabled: !_sending,
                              maxLength: 120,
                              textInputAction: TextInputAction.next,
                              decoration: _decoration(
                                s.t('feedbackSubjectHint'),
                                pill: true,
                              ),
                              validator: (text) =>
                                  (text?.trim().length ?? 0) < 5
                                  ? s.t('feedbackSubjectInvalid')
                                  : null,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            s.t('feedbackDescription'),
                            style: AppTextStyles.label,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Semantics(
                            label: s.t('feedbackDescription'),
                            child: TextFormField(
                              controller: _description,
                              enabled: !_sending,
                              maxLength: 5000,
                              minLines: 6,
                              maxLines: 12,
                              decoration: _decoration(
                                s.t(
                                  _kind == FeedbackKind.bug
                                      ? 'feedbackBugHint'
                                      : 'feedbackSuggestionHint',
                                ),
                              ),
                              validator: (text) =>
                                  (text?.trim().length ?? 0) < 10
                                  ? s.t('feedbackDescriptionInvalid')
                                  : null,
                            ),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              s.t('feedbackEnvironment'),
                              style: AppTextStyles.label,
                            ),
                            subtitle: Text(s.t('feedbackEnvironmentHint')),
                            value: _includeEnvironment,
                            onChanged: _sending
                                ? null
                                : (value) => setState(
                                    () => _includeEnvironment = value,
                                  ),
                          ),
                          if (_includeEnvironment)
                            FutureBuilder<String>(
                              future: _environment,
                              builder: (context, snapshot) => Text(
                                snapshot.data ?? '…',
                                style: AppTextStyles.bodySecondary.copyWith(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            s.t('feedbackPrivacy'),
                            style: AppTextStyles.bodySecondary.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              s.t('feedbackConsent'),
                              style: AppTextStyles.bodySecondary,
                            ),
                            value: _consent,
                            onChanged: _sending
                                ? null
                                : (value) =>
                                      setState(() => _consent = value ?? false),
                          ),
                          if (_errorKey != null || !_service.isConfigured)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.md,
                              ),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  s.t(_errorKey ?? 'feedbackNotConfigured'),
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                              ),
                            ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed:
                                _sending || !_consent || !_service.isConfigured
                                ? null
                                : _submit,
                            icon: _sending
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                            label: Text(
                              s.t(
                                _sending ? 'feedbackSending' : 'feedbackSubmit',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint, {bool pill = false}) {
    final border = OutlineInputBorder(
      borderRadius: pill ? BorderRadius.circular(999) : AppRadii.large,
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: context.appColors.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      disabledBorder: border,
      errorBorder: border,
      focusedErrorBorder: border,
    );
  }

  Widget _success(FeedbackReceipt receipt) {
    final s = context.strings;
    final colors = context.appColors;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      shrinkWrap: true,
      children: [
        Icon(Icons.check_circle_rounded, color: colors.lime, size: 64),
        const SizedBox(height: AppSpacing.lg),
        Text(
          s.t('feedbackSuccess'),
          textAlign: TextAlign.center,
          style: AppTextStyles.sectionTitle,
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            s
                .t('feedbackReceipt')
                .replaceAll('{number}', '${receipt.issueNumber}'),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: receipt.issueUrl.toString()),
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.t('feedbackLinkCopied'))),
              );
            }
          },
          child: Text(s.t('feedbackCopyLink')),
        ),
        FilledButton(
          onPressed: _close,
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text(s.t('feedbackDone')),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    minimumSize: const Size(64, 40),
                  )
                : FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Shows a single-field text dialog. Returns the trimmed text or null.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  String? label,
  String? hint,
  String confirmLabel = 'Save',
  int maxLength = 80,
  int maxLines = 1,
  bool allowEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      initialValue: initialValue,
      label: label,
      hint: hint,
      confirmLabel: confirmLabel,
      maxLength: maxLength,
      maxLines: maxLines,
      allowEmpty: allowEmpty,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.confirmLabel,
    required this.maxLength,
    required this.maxLines,
    required this.allowEmpty,
    this.initialValue,
    this.label,
    this.hint,
  });

  final String title;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String confirmLabel;
  final int maxLength;
  final int maxLines;
  final bool allowEmpty;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          maxLines: widget.maxLines,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          textInputAction:
              widget.maxLines == 1 ? TextInputAction.done : TextInputAction.newline,
          decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
          validator: (value) {
            if (!widget.allowEmpty && (value == null || value.trim().isEmpty)) {
              return 'Please enter a value';
            }
            return null;
          },
          onFieldSubmitted: (_) {
            if (widget.maxLines == 1) _submit();
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

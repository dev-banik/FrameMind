import 'package:flutter/material.dart';

/// Global messenger so services (e.g. push notifications) can show snackbars.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showAppSnackBar(
  String message, {
  bool isError = false,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  final context = rootScaffoldMessengerKey.currentContext;
  final scheme = context != null ? Theme.of(context).colorScheme : null;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: isError ? scheme?.error : null,
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                onPressed: onAction,
                textColor: isError ? scheme?.onError : null,
              )
            : null,
      ),
    );
}

import 'package:flutter/material.dart';

/// Brief toast-style snackbars so success feedback does not linger.
void showAppSnack(
  BuildContext context,
  String message, {
  bool error = false,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: action != null
          ? const Duration(seconds: 3)
          : error
              ? const Duration(milliseconds: 2200)
              : const Duration(milliseconds: 1400),
      action: action,
    ),
  );
}

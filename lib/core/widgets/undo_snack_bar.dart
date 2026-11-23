import 'package:flutter/material.dart';

/// How long an undo offer stays up: longer than a plain notice, so there is
/// time to notice a mis-tap and reach the button (D-064).
const Duration undoSnackBarDuration = Duration(seconds: 8);

/// Shows [message] with a 撤销 button that runs [onUndo] (D-064).
///
/// Pass the [messenger] captured before any `await`, so the offer still
/// works after the page that made the change has closed. A failing undo is
/// reported in a second snackbar instead of being lost.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showUndoSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  required Future<String?> Function() onUndo,
  Key? key,
}) {
  // Replace, not queue behind, whatever was showing: the offer is about
  // what the user just did.
  messenger.removeCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      key: key,
      content: Text(message),
      duration: undoSnackBarDuration,
      action: SnackBarAction(
        label: '撤销',
        onPressed: () async {
          String? result;
          try {
            result = await onUndo();
          } on Object catch (error) {
            result = '没能撤销：$error';
          }
          if (result != null && messenger.mounted) {
            messenger.showSnackBar(SnackBar(content: Text(result)));
          }
        },
      ),
    ),
  );
}

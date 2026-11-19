import 'package:material_ui/material_ui.dart';

/// The confirmation before leaving a room (or, for the host, closing it).
Future<bool> confirmLeaveOrClose(
  BuildContext context, {
  required bool isHost,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isHost ? 'Close room?' : 'Leave room?'),
      content: Text(
        isHost
            ? 'The room closes for everyone and its code stops working.'
            : 'You can rejoin later with the room code.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(isHost ? 'Close room' : 'Leave room'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

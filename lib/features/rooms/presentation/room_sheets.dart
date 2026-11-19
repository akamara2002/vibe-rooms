import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../auth/presentation/auth_providers.dart';
import '../domain/room_code.dart';
import '../domain/room_failure.dart';
import '../domain/room_name.dart';
import 'room_creator.dart';
import 'rooms_providers.dart';

Future<void> showCreateRoomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const CreateRoomSheet(),
  );
}

Future<void> showJoinRoomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const JoinRoomSheet(),
  );
}

/// Upper-cases input and drops characters that cannot be in a room code, so
/// typing or pasting "abc 234" gives "ABC234". Capped at six characters.
class RoomCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = normalizeRoomCode(newValue.text);
    if (text.length > roomCodeLength) text = text.substring(0, roomCodeLength);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

EdgeInsets _sheetPadding(BuildContext context) => EdgeInsets.fromLTRB(
  24,
  0,
  24,
  24 + MediaQuery.viewInsetsOf(context).bottom,
);

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Text(label),
      ),
    );
  }
}

class CreateRoomSheet extends ConsumerStatefulWidget {
  const CreateRoomSheet({super.key});

  @override
  ConsumerState<CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends ConsumerState<CreateRoomSheet> {
  late final TextEditingController _name;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final me = ref.read(myProfileProvider).value;
    final fallback = me == null ? 'My room' : "${me.displayName}'s room";
    _name = TextEditingController(text: fallback)
      ..selection = TextSelection(baseOffset: 0, extentOffset: fallback.length)
      ..addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => validateRoomName(_name.text) == null;

  Future<void> _create() async {
    if (!_valid || _busy) return;
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    // The sheet can be dismissed while the request runs, so `ref` must not be
    // used after the await: the container outlives the widget.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      final room = await container
          .read(roomCreatorProvider)
          .create(_name.text.trim());
      container.invalidate(myRoomsProvider);
      if (!mounted) return;
      navigator.pop();
      router.go('/room/${room.id}');
    } on RoomFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: _sheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create a room',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _name,
            autofocus: true,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validateRoomName,
            onFieldSubmitted: (_) => _create(),
            decoration: InputDecoration(
              labelText: 'Room name',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          _SheetButton(
            label: 'Create',
            busy: _busy,
            onPressed: _valid ? _create : null,
          ),
        ],
      ),
    );
  }
}

class JoinRoomSheet extends ConsumerStatefulWidget {
  const JoinRoomSheet({super.key});

  @override
  ConsumerState<JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends ConsumerState<JoinRoomSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _valid => isValidRoomCode(_code.text);

  Future<void> _join() async {
    if (!_valid || _busy) return;
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      final room = await container
          .read(roomRepositoryProvider)
          .joinRoom(_code.text);
      container.invalidate(myRoomsProvider);
      if (!mounted) return;
      navigator.pop();
      router.go('/room/${room.id}');
    } on RoomFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: _sheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Join with a code',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            autofocus: true,
            enabled: !_busy,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [RoomCodeFormatter()],
            onSubmitted: (_) => _join(),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: 'ABC234',
              errorText: _error,
              helperText: '6 characters, letters and numbers',
              helperMaxLines: 1,
            ),
          ),
          const SizedBox(height: 16),
          _SheetButton(
            label: 'Join',
            busy: _busy,
            onPressed: _valid ? _join : null,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/supabase_client.dart';
import '../../../core/widgets/config_banner.dart';
import '../../../core/widgets/gradient_background.dart';
import '../domain/auth_failure.dart';
import '../domain/validators.dart';
import 'auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_rebuild);
  final _guestName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _newName = TextEditingController();

  bool _creating = false;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_guestName, _email, _password, _newName]) {
      c.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _guestName.dispose();
    _email.dispose();
    _password.dispose();
    _newName.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool get _ready => ref.read(supabaseReadyProvider);

  bool get _canGuest =>
      _ready && !_busy && validateDisplayName(_guestName.text) == null;

  bool get _canEmail =>
      _ready &&
      !_busy &&
      validateEmail(_email.text) == null &&
      validatePassword(_password.text) == null &&
      (!_creating || validateDisplayName(_newName.text) == null);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a sign-in action with a loading state and friendly errors.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on AuthFailure catch (failure) {
      _snack(failure.message);
      if (failure.kind == AuthFailureKind.emailConfirmationRequired &&
          mounted) {
        setState(() => _creating = false);
      }
    } catch (error) {
      // Never log request data: only the error type.
      debugPrint('Sign-in failed (${error.runtimeType})');
      _snack(const AuthFailure(AuthFailureKind.unknown).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueAsGuest() {
    if (!_canGuest) return;
    final auth = ref.read(authRepositoryProvider);
    _run(() => auth.signInAsGuest(_guestName.text.trim()));
  }

  void _submitEmail() {
    if (!_canEmail) return;
    final auth = ref.read(authRepositoryProvider);
    if (_creating) {
      _run(
        () => auth.signUpWithEmail(
          _email.text.trim(),
          _password.text,
          _newName.text.trim(),
        ),
      );
    } else {
      _run(() => auth.signInWithEmail(_email.text.trim(), _password.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ready = ref.watch(supabaseReadyProvider);
    final configured = ref.watch(configProvider).isConfigured;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      // The app icon itself, so the login screen and the launcher
                      // icon agree. Decorative: the title below names the app.
                      child: ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/icon/mark.png',
                            width: 96,
                            height: 96,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Vibe Rooms',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Listen together, anywhere.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (!ready) ...[
                      _NotReadyNotice(configured: configured),
                      const SizedBox(height: 16),
                    ],
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TabBar(
                              controller: _tabs,
                              dividerColor: Colors.transparent,
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelColor: scheme.onPrimaryContainer,
                              tabs: const [
                                Tab(text: 'Quick start'),
                                Tab(text: 'Email'),
                              ],
                            ),
                            const SizedBox(height: 20),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: _tabs.index == 0
                                  ? _quickStart()
                                  : _emailForm(),
                            ),
                          ],
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

  Widget _quickStart() {
    return Column(
      key: const ValueKey('quick-start'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _guestName,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validateDisplayName,
          onFieldSubmitted: (_) => _continueAsGuest(),
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: 'Continue as guest',
          busy: _busy,
          onPressed: _canGuest ? _continueAsGuest : null,
        ),
      ],
    );
  }

  Widget _emailForm() {
    return AutofillGroup(
      key: const ValueKey('email'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Sign in')),
              ButtonSegment(value: true, label: Text('Create account')),
            ],
            selected: {_creating},
            onSelectionChanged: _busy
                ? null
                : (value) => setState(() => _creating = value.first),
          ),
          const SizedBox(height: 16),
          if (_creating) ...[
            TextFormField(
              controller: _newName,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: validateDisplayName,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validateEmail,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            enabled: !_busy,
            obscureText: !_showPassword,
            autofillHints: [
              _creating ? AutofillHints.newPassword : AutofillHints.password,
            ],
            textInputAction: TextInputAction.done,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validatePassword,
            onFieldSubmitted: (_) => _submitEmail(),
            inputFormatters: [FilteringTextInputFormatter.deny('\n')],
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: _creating ? 'Create account' : 'Sign in',
            busy: _busy,
            onPressed: _canEmail ? _submitEmail : null,
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
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

/// Shown when Supabase is missing or could not start. Sign-in is disabled.
class _NotReadyNotice extends StatelessWidget {
  const _NotReadyNotice({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                configured
                    ? 'Could not connect to Supabase. Check your keys and connection, then restart the app.'
                    : configBannerMessage,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

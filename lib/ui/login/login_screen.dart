import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:tdlib/td_api.dart' as td;

import '../../tdlib/telegram_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController(text: '+');
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<TelegramClient>();
    final state = client.authState;
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.primary.withValues(alpha: 0.08),
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'TG Focus',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.ibmPlexSerif(
                        fontSize: 40,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Only the groups you choose.\nNothing else.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 36),
                    if (client.lastError != null) ...[
                      Material(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            client.lastError!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (state == null ||
                        state is td.AuthorizationStateWaitTdlibParameters)
                      const Center(child: CircularProgressIndicator())
                    else if (state is td.AuthorizationStateWaitPhoneNumber)
                      _PhoneForm(
                        controller: _phoneController,
                        busy: _busy,
                        onSubmit: () => _run(
                          () => client.submitPhoneNumber(_phoneController.text),
                        ),
                      )
                    else if (state is td.AuthorizationStateWaitCode)
                      _CodeForm(
                        controller: _codeController,
                        busy: _busy,
                        onSubmit: () =>
                            _run(() => client.submitCode(_codeController.text)),
                      )
                    else if (state is td.AuthorizationStateWaitPassword)
                      _PasswordForm(
                        controller: _passwordController,
                        hint: state.passwordHint,
                        busy: _busy,
                        onSubmit: () => _run(
                          () => client.submitPassword(_passwordController.text),
                        ),
                      )
                    else if (state is td.AuthorizationStateWaitRegistration)
                      Text(
                        'Finish registration in the official Telegram app, then return here.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      )
                    else if (state
                        is td.AuthorizationStateWaitOtherDeviceConfirmation)
                      Text(
                        'Confirm login on another device.\n${state.link}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      )
                    else
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneForm extends StatelessWidget {
  const _PhoneForm({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '+2519...',
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}

class _CodeForm extends StatelessWidget {
  const _CodeForm({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Login code'),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify'),
        ),
      ],
    );
  }
}

class _PasswordForm extends StatelessWidget {
  const _PasswordForm({
    required this.controller,
    required this.hint,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String hint;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          obscureText: true,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: '2FA password',
            hintText: hint.isEmpty ? null : 'Hint: $hint',
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Unlock'),
        ),
      ],
    );
  }
}

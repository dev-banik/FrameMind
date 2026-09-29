import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/app_logo.dart';
import '../providers/auth_providers.dart';

enum _AuthAction { google, apple, email, reset }

/// Google / Apple (iOS only) / Email sign-in. Navigation happens automatically
/// through the router once Firebase reports a signed-in user.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _registerMode = false;
  bool _obscurePassword = true;
  _AuthAction? _busy;

  bool get _showApple => !kIsWeb && Platform.isIOS;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(_AuthAction action, Future<void> Function() task) async {
    if (_busy != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = action);
    try {
      await task();
    } catch (e) {
      if (mounted) _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _showError(String message) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: scheme.error,
      ));
  }

  Future<void> _google() => _run(_AuthAction.google, () async {
        await ref.read(authRepositoryProvider).signInWithGoogle();
      });

  Future<void> _apple() => _run(_AuthAction.apple, () async {
        await ref.read(authRepositoryProvider).signInWithApple();
      });

  Future<void> _email() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(_AuthAction.email, () async {
      final repo = ref.read(authRepositoryProvider);
      if (_registerMode) {
        await repo.registerWithEmail(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await repo.signInWithEmail(_emailController.text, _passwordController.text);
      }
    });
  }

  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initialEmail: _emailController.text),
    );
    if (email == null || !mounted) return;
    await _run(_AuthAction.reset, () async {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset link sent to $email')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _busy != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 76)),
                  const SizedBox(height: 20),
                  Text(
                    _registerMode ? 'Create your account' : 'Welcome to FrameMind',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Paste any video for inspiration. Get a 100% original script and AI video.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SocialButton(
                    label: 'Continue with Google',
                    icon: const Text(
                      'G',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                    loading: _busy == _AuthAction.google,
                    onPressed: busy ? null : _google,
                  ),
                  if (_showApple) ...[
                    const SizedBox(height: 12),
                    _SocialButton(
                      label: 'Continue with Apple',
                      icon: const Icon(Icons.apple, size: 24),
                      loading: _busy == _AuthAction.apple,
                      onPressed: busy ? null : _apple,
                      dark: true,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or use email',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        children: [
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            child: _registerMode
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TextFormField(
                                      controller: _nameController,
                                      textCapitalization: TextCapitalization.words,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.name],
                                      decoration: const InputDecoration(
                                        labelText: 'Your name',
                                        prefixIcon: Icon(Icons.person_outline),
                                      ),
                                      validator: (v) => _registerMode &&
                                              (v == null || v.trim().isEmpty)
                                          ? 'Please enter your name'
                                          : null,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: [
                              _registerMode
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            onFieldSubmitted: (_) => _email(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () =>
                                    setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Please enter your password';
                              if (_registerMode && v.length < 6) {
                                return 'Use at least 6 characters';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_registerMode)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy ? null : _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : _email,
                    child: _busy == _AuthAction.email
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(_registerMode ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _registerMode ? 'Already have an account?' : 'New to FrameMind?',
                        style: theme.textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => _registerMode = !_registerMode),
                        child: Text(_registerMode ? 'Sign in' : 'Create account'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please enter your email';
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
    return valid ? null : 'Please enter a valid email';
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
    this.dark = false,
  });

  final String label;
  final Widget icon;
  final bool loading;
  final VoidCallback? onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final style = dark
        ? OutlinedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            minimumSize: const Size(64, 52),
            side: BorderSide.none,
          )
        : OutlinedButton.styleFrom(minimumSize: const Size(64, 52));
    return OutlinedButton(
      style: style,
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            icon,
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialEmail);
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
      title: const Text('Reset password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your account email and we'll send you a reset link."),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: _LoginScreenState._validateEmail,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
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
          child: const Text('Send link'),
        ),
      ],
    );
  }
}

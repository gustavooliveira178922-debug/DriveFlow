import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../app/theme.dart';
import '../../services/native_bridge.dart';
import '../../services/telegram_service.dart';
import '../../services/google_account_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onConnected, super.key});
  final VoidCallback onConnected;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _passwordRequired = false;
  bool _googleBusy = false;
  GoogleAccount? _googleAccount;
  String? _googleClientId;
  bool _busy = false;
  String? _lastTelegramError;
  TelegramAuthStep _step = TelegramAuthStep.starting;
  final _telegram = TelegramService(NativeBridge.load());
  final _google = GoogleAccountService();
  static const _secureStorage = FlutterSecureStorage();
  static const _googleClientIdKey = 'driveflow.google.oauth_client_id';
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _telegram.initialize().catchError((Object error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start Telegram: $error')));
    });
    _loadGoogleClientId();
    _poller = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      final step = _telegram.authStep;
      final telegramError = _telegram.lastError;
      if (telegramError != null && telegramError != _lastTelegramError) {
        _lastTelegramError = telegramError;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Telegram: $telegramError')));
      }
      if (step == TelegramAuthStep.ready && _googleAccount != null) {
        _poller?.cancel();
        widget.onConnected();
      } else {
        setState(() {
          _step = step;
          _codeSent = step == TelegramAuthStep.waitingForCode || step == TelegramAuthStep.waitingForPassword;
          _passwordRequired = step == TelegramAuthStep.waitingForPassword;
        });
      }
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _connectGoogle() async {
    var clientId = GoogleAccountService.clientId.isNotEmpty ? GoogleAccountService.clientId : _googleClientId;
    if (clientId == null || clientId.trim().isEmpty) {
      final controller = TextEditingController();
      clientId = await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: const Text('Set up Google sign-in'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Google OAuth client ID', hintText: '...apps.googleusercontent.com')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Continue'))],
      ));
      controller.dispose();
      if (clientId == null || clientId.isEmpty) return;
      await _secureStorage.write(key: _googleClientIdKey, value: clientId);
      _googleClientId = clientId;
    }
    setState(() => _googleBusy = true);
    try {
      final account = await _google.signIn(clientIdOverride: clientId);
      if (mounted) setState(() {
        _googleAccount = account;
        final phoneNumber = account.phoneNumber;
        if (phoneNumber != null && phoneNumber.trim().isNotEmpty) _phone.text = phoneNumber;
      });
    } on Object catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _loadGoogleClientId() async {
    if (GoogleAccountService.clientId.isNotEmpty) return;
    final clientId = await _secureStorage.read(key: _googleClientIdKey);
    if (mounted && clientId != null && clientId.isNotEmpty) setState(() => _googleClientId = clientId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                return Row(children: [
                if (!compact)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 56),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      _Brand(),
                      const SizedBox(height: 72),
                      Text('Your files.\nYour Telegram.', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 48, height: 1.08)),
                      const SizedBox(height: 20),
                      const Text('A calm, private workspace for the files you send to your own chats. Stored directly in your Telegram account.', style: TextStyle(color: DriveFlowTheme.muted, fontSize: 16, height: 1.6)),
                      const SizedBox(height: 32),
                      const _Feature(icon: Icons.lock_outline, title: 'Your account, your control', body: 'Connect directly to Telegram. No relay server.'),
                      const SizedBox(height: 15),
                      const _Feature(icon: Icons.cloud_upload_outlined, title: 'No subscriptions or ads', body: 'DriveFlow is free to use.'),
                    ]),
                  ),
                ),
                Flexible(
                  child: SizedBox(
                  width: compact ? constraints.maxWidth : 380,
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(color: DriveFlowTheme.panel.withValues(alpha: .92), borderRadius: BorderRadius.circular(24), border: Border.all(color: DriveFlowTheme.line)),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (compact) ...[_Brand(), const SizedBox(height: 28)],
                      Text(_passwordRequired ? 'Enter your password' : _codeSent ? 'Check your Telegram' : 'Connect Telegram', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Text(_passwordRequired ? 'Your account has two-step verification enabled.' : _codeSent ? 'Enter the sign-in code sent to your account.' : _step == TelegramAuthStep.starting ? 'Connecting securely to Telegram…' : 'Connect a Google account, then verify your Telegram phone number to open Saved Messages.', style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 26),
                      if (!_codeSent && !_passwordRequired) ...[
                        SizedBox(width: double.infinity, height: 46, child: OutlinedButton.icon(
                          onPressed: _googleBusy ? null : _connectGoogle,
                          icon: _googleBusy ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.account_circle_outlined),
                          label: Text(_googleAccount == null ? 'Continue with Google' : 'Google · ${_googleAccount!.email}', overflow: TextOverflow.ellipsis),
                        )),
                        const SizedBox(height: 10),
                        const Text('Google can share a phone number to prefill this field. Confirm the number, then Telegram will verify it with a sign-in code.', style: TextStyle(color: DriveFlowTheme.muted, fontSize: 11, height: 1.5)),
                        const SizedBox(height: 20),
                      ],
                      if (_passwordRequired) ...[
                        const Text('TWO-STEP VERIFICATION', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: DriveFlowTheme.muted)),
                        const SizedBox(height: 8),
                        TextField(controller: _password, obscureText: true, decoration: const InputDecoration(hintText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
                      ] else if (!_codeSent) ...[
                        const Text('PHONE NUMBER', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: DriveFlowTheme.muted)),
                        const SizedBox(height: 8),
                        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '+1 555 000 0000', prefixIcon: Icon(Icons.phone_iphone))),
                      ] else ...[
                        const Text('LOGIN CODE', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: DriveFlowTheme.muted)),
                        const SizedBox(height: 8),
                        TextField(controller: _code, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Enter code', prefixIcon: Icon(Icons.password))),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _busy || (_step == TelegramAuthStep.waitingForPhone && _googleAccount == null) || !(_step == TelegramAuthStep.waitingForPhone || _step == TelegramAuthStep.waitingForCode || _step == TelegramAuthStep.waitingForPassword) ? null : () async {
                        setState(() => _busy = true);
                        try {
                          if (_passwordRequired) {
                            await _telegram.submitPassword(_password.text);
                          } else if (_codeSent) {
                            await _telegram.submitCode(_code.text.trim());
                          } else {
                            await _telegram.submitPhoneNumber(_phone.text.trim());
                          }
                        } on Object catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Telegram sign-in failed: $error')));
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      }, child: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_passwordRequired ? 'Verify password' : _codeSent ? 'Verify code' : 'Continue'))),
                      const SizedBox(height: 14),
                      const Text('Authentication is handled by Telegram. Your code is never sent to DriveFlow servers.', textAlign: TextAlign.center, style: TextStyle(color: DriveFlowTheme.muted, fontSize: 11, height: 1.5)),
                    ]),
                  ),
                  ),
                ),
              ]);
              }),
            ),
          )),
        ),
      );
}

class _Brand extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: DriveFlowTheme.accent, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.cloud_done_rounded, color: DriveFlowTheme.background)),
        const SizedBox(width: 12),
        const Text('driveflow', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -.5)),
      ]);
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: DriveFlowTheme.accent, size: 19),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), Text(body, style: Theme.of(context).textTheme.bodyMedium)])),
      ]);
}

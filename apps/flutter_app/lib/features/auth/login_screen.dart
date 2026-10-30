import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/native_bridge.dart';
import '../../services/telegram_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onConnected, super.key});
  final VoidCallback onConnected;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  final _telegram = TelegramService(NativeBridge.load());

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
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
                      Text(_codeSent ? 'Check your Telegram' : 'Connect Telegram', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Text(_codeSent ? 'Enter the sign-in code sent to your account.' : 'Use your phone number to sign in securely.', style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 26),
                      if (!_codeSent) ...[
                        const Text('PHONE NUMBER', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: DriveFlowTheme.muted)),
                        const SizedBox(height: 8),
                        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '+1 555 000 0000', prefixIcon: Icon(Icons.phone_iphone))),
                      ] else ...[
                        const Text('LOGIN CODE', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: DriveFlowTheme.muted)),
                        const SizedBox(height: 8),
                        TextField(controller: _code, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Enter code', prefixIcon: Icon(Icons.password))),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: () async {
                        try {
                          if (_codeSent) {
                            await _telegram.submitCode(_code.text.trim());
                            if (_telegram.authStep == TelegramAuthStep.ready) widget.onConnected();
                          } else {
                            await _telegram.submitPhoneNumber(_phone.text.trim());
                            setState(() => _codeSent = true);
                          }
                        } on Object catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Telegram sign-in is not configured yet: $error')));
                        }
                      }, child: Text(_codeSent ? 'Verify code' : 'Continue'))),
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

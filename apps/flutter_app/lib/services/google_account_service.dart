import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleAccount {
  const GoogleAccount({required this.email, required this.name, this.phoneNumber});
  final String email;
  final String name;
  final String? phoneNumber;
}

/// Google identifies the app user only. Telegram still requires its own phone
/// number and verification code before any Telegram data can be accessed.
/// OAuth runs in the user's system browser with a loopback callback, never a
/// WebView. The Google OAuth client ID must be configured by the app owner.
class GoogleAccountService {
  static const clientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
  static const _scopes = 'openid email profile https://www.googleapis.com/auth/user.phonenumbers.read';

  Future<GoogleAccount> signIn({String? clientIdOverride}) async {
    final oauthClientId = clientIdOverride ?? clientId;
    if (oauthClientId.isEmpty) {
      throw StateError('Enter the Google OAuth client ID from your Google Cloud project.');
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    final redirectUri = 'http://127.0.0.1:${server.port}/oauth2redirect';
    final state = _randomToken(32);
    final verifier = _randomToken(64);
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    try {
      final authorizationUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': oauthClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': _scopes,
        // Always show Google's account chooser, even if the default browser
        // already has an active Google session.
        'prompt': 'select_account',
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'online',
      });
      if (!await launchUrl(authorizationUri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open the system browser for Google sign-in.');
      }

      String? code;
      await for (final request in server.timeout(const Duration(minutes: 3))) {
        if (request.uri.path != '/oauth2redirect') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
        }
        if (request.uri.queryParameters['state'] != state) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('The sign-in state did not match. Return to DriveFlow and try again.');
          await request.response.close();
          throw StateError('Google sign-in could not verify the browser callback.');
        }
        final providerError = request.uri.queryParameters['error'];
        if (providerError != null) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('Google sign-in was cancelled or denied. You can close this tab.');
          await request.response.close();
          throw StateError('Google sign-in failed: $providerError');
        }
        code = request.uri.queryParameters['code'];
        request.response.headers.contentType = ContentType.html;
        request.response.write('<!doctype html><title>DriveFlow</title><p>Google account connected. You can return to DriveFlow.</p>');
        await request.response.close();
        break;
      }
      if (code == null || code.isEmpty) throw StateError('Google sign-in timed out. Please try again.');
      return await _exchangeCode(code, verifier, redirectUri, oauthClientId);
    } finally {
      await server.close(force: true);
    }
  }

  Future<GoogleAccount> _exchangeCode(String code, String verifier, String redirectUri, String oauthClientId) async {
    final client = HttpClient();
    try {
      final tokenRequest = await client.postUrl(Uri.https('oauth2.googleapis.com', '/token'));
      tokenRequest.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      tokenRequest.write(Uri(queryParameters: {
        'client_id': oauthClientId,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      }).query);
      final tokenResponse = await tokenRequest.close();
      final tokenJson = jsonDecode(await tokenResponse.transform(utf8.decoder).join()) as Map<String, dynamic>;
      if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
        throw StateError('Google token exchange failed: ${tokenJson['error_description'] ?? tokenJson['error'] ?? tokenResponse.statusCode}');
      }
      final accessToken = tokenJson['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) throw StateError('Google did not return an access token.');
      final profileRequest = await client.getUrl(Uri.https('openidconnect.googleapis.com', '/v1/userinfo'));
      profileRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      final profileResponse = await profileRequest.close();
      final profile = jsonDecode(await profileResponse.transform(utf8.decoder).join()) as Map<String, dynamic>;
      if (profileResponse.statusCode < 200 || profileResponse.statusCode >= 300 || profile['email_verified'] != true) {
        throw StateError('Google could not verify the account email.');
      }
      final phone = await _readPhoneNumber(client, accessToken);
      return GoogleAccount(email: profile['email'] as String, name: (profile['name'] as String?) ?? 'Google account', phoneNumber: phone);
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _readPhoneNumber(HttpClient client, String accessToken) async {
    final request = await client.getUrl(Uri.https('people.googleapis.com', '/v1/people/me', {'personFields': 'phoneNumbers'}));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      return null;
    }
    final payload = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final numbers = payload['phoneNumbers'] as List<dynamic>? ?? const [];
    if (numbers.isEmpty) return null;
    final primary = numbers.cast<Map<String, dynamic>>().where((entry) => entry['metadata'] is Map<String, dynamic> && (entry['metadata'] as Map<String, dynamic>)['primary'] == true);
    final selected = primary.isNotEmpty ? primary.first : numbers.first as Map<String, dynamic>;
    return selected['value'] as String?;
  }

  String _randomToken(int length) {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(length, (_) => random.nextInt(256))).replaceAll('=', '');
  }
}

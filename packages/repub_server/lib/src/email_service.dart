import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:repub_storage/repub_storage.dart';

import 'logger.dart';

/// SMTP configuration loaded from site config.
class SmtpConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final String fromAddress;
  final String fromName;
  final bool ssl;
  final bool enabled;
  final bool onPackagePublished;
  final bool onUserRegistered;

  SmtpConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.fromAddress,
    required this.fromName,
    required this.ssl,
    required this.enabled,
    required this.onPackagePublished,
    required this.onUserRegistered,
  });

  /// Check if SMTP is properly configured.
  bool get isConfigured =>
      host.isNotEmpty && fromAddress.isNotEmpty && enabled;

  /// Create from site config map.
  factory SmtpConfig.fromConfigMap(Map<String, String> config) {
    return SmtpConfig(
      host: config['smtp_host'] ?? '',
      port: int.tryParse(config['smtp_port'] ?? '') ?? 587,
      username: config['smtp_username'] ?? '',
      password: config['smtp_password'] ?? '',
      fromAddress: config['smtp_from_address'] ?? '',
      fromName: config['smtp_from_name'] ?? 'Repub Package Registry',
      ssl: config['smtp_ssl']?.toLowerCase() == 'true',
      enabled: config['email_notifications_enabled']?.toLowerCase() == 'true',
      onPackagePublished:
          config['email_on_package_published']?.toLowerCase() != 'false',
      onUserRegistered:
          config['email_on_user_registered']?.toLowerCase() != 'false',
    );
  }
}

/// Service for sending email notifications.
class EmailService {
  final MetadataStore metadata;
  SmtpConfig? _cachedConfig;
  DateTime? _configCachedAt;

  /// Cache duration for SMTP config.
  static const _configCacheDuration = Duration(minutes: 5);

  EmailService({required this.metadata});

  /// Get SMTP configuration from database, with caching.
  Future<SmtpConfig> _getConfig() async {
    final now = DateTime.now();
    if (_cachedConfig != null &&
        _configCachedAt != null &&
        now.difference(_configCachedAt!) < _configCacheDuration) {
      return _cachedConfig!;
    }

    final allConfig = await metadata.getAllConfig();
    final configMap = <String, String>{};
    for (final config in allConfig) {
      configMap[config.name] = config.value;
    }

    _cachedConfig = SmtpConfig.fromConfigMap(configMap);
    _configCachedAt = now;
    return _cachedConfig!;
  }

  /// Get SMTP server configuration.
  SmtpServer _getSmtpServer(SmtpConfig config) {
    if (config.ssl) {
      return SmtpServer(
        config.host,
        port: config.port,
        username: config.username.isNotEmpty ? config.username : null,
        password: config.password.isNotEmpty ? config.password : null,
        ssl: true,
        allowInsecure: false,
      );
    } else {
      return SmtpServer(
        config.host,
        port: config.port,
        username: config.username.isNotEmpty ? config.username : null,
        password: config.password.isNotEmpty ? config.password : null,
        ssl: false,
        allowInsecure: true,
      );
    }
  }

  /// Send an email.
  Future<bool> _send(Message message) async {
    final config = await _getConfig();
    if (!config.isConfigured) {
      Logger.debug(
        'Email not sent: SMTP not configured or disabled',
        component: 'email',
      );
      return false;
    }

    try {
      final smtpServer = _getSmtpServer(config);
      await send(message, smtpServer);

      Logger.info(
        'Email sent successfully',
        component: 'email',
        metadata: {
          'to': message.recipients.map((a) => a.toString()).join(', '),
          'subject': message.subject,
        },
      );

      return true;
    } catch (e, stack) {
      Logger.error(
        'Failed to send email',
        component: 'email',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Get the configured from address.
  Future<Address> _getFromAddress() async {
    final config = await _getConfig();
    return Address(config.fromAddress, config.fromName);
  }

  /// Send notification when a package is published.
  Future<void> onPackagePublished({
    required String packageName,
    required String version,
    required String publisherEmail,
    String? baseUrl,
  }) async {
    final config = await _getConfig();
    if (!config.isConfigured || !config.onPackagePublished) {
      return;
    }

    final packageUrl = baseUrl != null
        ? '$baseUrl/packages/$packageName'
        : '/packages/$packageName';

    final message = Message()
      ..from = await _getFromAddress()
      ..recipients.add(publisherEmail)
      ..subject = 'Package Published: $packageName@$version'
      ..text = '''
Hello,

Your package has been successfully published to the Repub Package Registry.

Package: $packageName
Version: $version
Published: ${DateTime.now().toUtc().toIso8601String()}

View your package: $packageUrl

Thank you for using Repub!

---
This is an automated message from Repub Package Registry.
''';

    await _send(message);
  }

  /// Send welcome email when a user registers.
  Future<void> onUserRegistered({
    required String email,
    required String name,
    String? baseUrl,
  }) async {
    final config = await _getConfig();
    if (!config.isConfigured || !config.onUserRegistered) {
      return;
    }

    final dashboardUrl = baseUrl != null ? '$baseUrl/account' : '/account';

    final message = Message()
      ..from = await _getFromAddress()
      ..recipients.add(email)
      ..subject = 'Welcome to Repub Package Registry'
      ..text = '''
Hello${name.isNotEmpty ? ' $name' : ''},

Welcome to Repub Package Registry! Your account has been created successfully.

Email: $email
Registered: ${DateTime.now().toUtc().toIso8601String()}

To get started:
1. Create an API token in your account dashboard
2. Configure your Dart/Flutter project to use this registry
3. Publish your first package!

Account Dashboard: $dashboardUrl

Thank you for joining Repub!

---
This is an automated message from Repub Package Registry.
''';

    await _send(message);
  }

  /// Send email verification (for future email verification feature).
  Future<void> sendVerificationEmail({
    required String email,
    required String verificationCode,
    String? baseUrl,
  }) async {
    final config = await _getConfig();
    if (!config.isConfigured) {
      return;
    }

    final verifyUrl = baseUrl != null
        ? '$baseUrl/verify?code=$verificationCode'
        : '/verify?code=$verificationCode';

    final message = Message()
      ..from = await _getFromAddress()
      ..recipients.add(email)
      ..subject = 'Verify Your Email - Repub Package Registry'
      ..text = '''
Hello,

Please verify your email address by clicking the link below:

$verifyUrl

Or enter this verification code: $verificationCode

This link will expire in 24 hours.

If you didn't create an account, please ignore this email.

---
This is an automated message from Repub Package Registry.
''';

    await _send(message);
  }

  /// Send password reset email (for future password reset feature).
  Future<void> sendPasswordResetEmail({
    required String email,
    required String resetToken,
    String? baseUrl,
  }) async {
    final config = await _getConfig();
    if (!config.isConfigured) {
      return;
    }

    final resetUrl = baseUrl != null
        ? '$baseUrl/reset-password?token=$resetToken'
        : '/reset-password?token=$resetToken';

    final message = Message()
      ..from = await _getFromAddress()
      ..recipients.add(email)
      ..subject = 'Password Reset - Repub Package Registry'
      ..text = '''
Hello,

We received a request to reset your password. Click the link below to set a new password:

$resetUrl

This link will expire in 1 hour.

If you didn't request a password reset, please ignore this email. Your password will remain unchanged.

---
This is an automated message from Repub Package Registry.
''';

    await _send(message);
  }

  /// Send notification to admins when a new user registers.
  Future<void> notifyAdminsOfNewUser({
    required String userEmail,
    required String userName,
    required List<String> adminEmails,
    String? baseUrl,
  }) async {
    final config = await _getConfig();
    if (!config.isConfigured || adminEmails.isEmpty) {
      return;
    }

    final usersUrl =
        baseUrl != null ? '$baseUrl/admin/users' : '/admin/users';

    final message = Message()
      ..from = await _getFromAddress()
      ..recipients.addAll(adminEmails)
      ..subject = 'New User Registration - Repub Package Registry'
      ..text = '''
A new user has registered on the Repub Package Registry.

Name: $userName
Email: $userEmail
Registered: ${DateTime.now().toUtc().toIso8601String()}

Manage users: $usersUrl

---
This is an automated message from Repub Package Registry.
''';

    await _send(message);
  }

  /// Clear the config cache (useful after config updates).
  void clearConfigCache() {
    _cachedConfig = null;
    _configCachedAt = null;
    Logger.debug('Email config cache cleared', component: 'email');
  }
}

import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

import 'package:repub_server/src/email_service.dart';

void main() {
  group('SmtpConfig', () {
    test('fromConfigMap parses all config values correctly', () {
      final configMap = {
        'smtp_host': 'smtp.example.com',
        'smtp_port': '465',
        'smtp_username': 'user@example.com',
        'smtp_password': 'secret123',
        'smtp_from_address': 'noreply@example.com',
        'smtp_from_name': 'Test Registry',
        'smtp_ssl': 'true',
        'email_notifications_enabled': 'true',
        'email_on_package_published': 'true',
        'email_on_user_registered': 'false',
      };

      final config = SmtpConfig.fromConfigMap(configMap);

      expect(config.host, 'smtp.example.com');
      expect(config.port, 465);
      expect(config.username, 'user@example.com');
      expect(config.password, 'secret123');
      expect(config.fromAddress, 'noreply@example.com');
      expect(config.fromName, 'Test Registry');
      expect(config.ssl, true);
      expect(config.enabled, true);
      expect(config.onPackagePublished, true);
      expect(config.onUserRegistered, false);
    });

    test('fromConfigMap uses defaults for missing values', () {
      final config = SmtpConfig.fromConfigMap({});

      expect(config.host, '');
      expect(config.port, 587);
      expect(config.username, '');
      expect(config.password, '');
      expect(config.fromAddress, '');
      expect(config.fromName, 'Repub Package Registry');
      expect(config.ssl, false);
      expect(config.enabled, false);
      expect(config.onPackagePublished, true);
      expect(config.onUserRegistered, true);
    });

    test('isConfigured returns true when host, fromAddress, and enabled', () {
      final configMap = {
        'smtp_host': 'smtp.example.com',
        'smtp_from_address': 'noreply@example.com',
        'email_notifications_enabled': 'true',
      };

      final config = SmtpConfig.fromConfigMap(configMap);
      expect(config.isConfigured, true);
    });

    test('isConfigured returns false when host is empty', () {
      final configMap = {
        'smtp_from_address': 'noreply@example.com',
        'email_notifications_enabled': 'true',
      };

      final config = SmtpConfig.fromConfigMap(configMap);
      expect(config.isConfigured, false);
    });

    test('isConfigured returns false when fromAddress is empty', () {
      final configMap = {
        'smtp_host': 'smtp.example.com',
        'email_notifications_enabled': 'true',
      };

      final config = SmtpConfig.fromConfigMap(configMap);
      expect(config.isConfigured, false);
    });

    test('isConfigured returns false when disabled', () {
      final configMap = {
        'smtp_host': 'smtp.example.com',
        'smtp_from_address': 'noreply@example.com',
        'email_notifications_enabled': 'false',
      };

      final config = SmtpConfig.fromConfigMap(configMap);
      expect(config.isConfigured, false);
    });

    test('parses port correctly with invalid value', () {
      final config = SmtpConfig.fromConfigMap({'smtp_port': 'invalid'});
      expect(config.port, 587); // Falls back to default
    });

    test('parses ssl correctly with different values', () {
      expect(
        SmtpConfig.fromConfigMap({'smtp_ssl': 'true'}).ssl,
        true,
      );
      expect(
        SmtpConfig.fromConfigMap({'smtp_ssl': 'TRUE'}).ssl,
        true,
      );
      expect(
        SmtpConfig.fromConfigMap({'smtp_ssl': 'false'}).ssl,
        false,
      );
      expect(
        SmtpConfig.fromConfigMap({'smtp_ssl': '1'}).ssl,
        false,
      );
    });
  });

  group('SiteConfigDefaults', () {
    test('contains SMTP configuration entries', () {
      final configNames = SiteConfigDefaults.all.map((c) => c.name).toList();

      expect(configNames, contains('smtp_host'));
      expect(configNames, contains('smtp_port'));
      expect(configNames, contains('smtp_username'));
      expect(configNames, contains('smtp_password'));
      expect(configNames, contains('smtp_from_address'));
      expect(configNames, contains('smtp_from_name'));
      expect(configNames, contains('smtp_ssl'));
      expect(configNames, contains('email_notifications_enabled'));
      expect(configNames, contains('email_on_package_published'));
      expect(configNames, contains('email_on_user_registered'));
    });

    test('smtp_port has correct default value', () {
      final portConfig = SiteConfigDefaults.all.firstWhere(
        (c) => c.name == 'smtp_port',
      );
      expect(portConfig.value, '587');
      expect(portConfig.valueType, ConfigValueType.number);
    });

    test('smtp_from_name has correct default value', () {
      final nameConfig = SiteConfigDefaults.all.firstWhere(
        (c) => c.name == 'smtp_from_name',
      );
      expect(nameConfig.value, 'Repub Package Registry');
      expect(nameConfig.valueType, ConfigValueType.string);
    });

    test('email_notifications_enabled defaults to false', () {
      final config = SiteConfigDefaults.all.firstWhere(
        (c) => c.name == 'email_notifications_enabled',
      );
      expect(config.value, 'false');
      expect(config.valueType, ConfigValueType.boolean);
    });

    test('email_on_package_published defaults to true', () {
      final config = SiteConfigDefaults.all.firstWhere(
        (c) => c.name == 'email_on_package_published',
      );
      expect(config.value, 'true');
      expect(config.valueType, ConfigValueType.boolean);
    });

    test('email_on_user_registered defaults to true', () {
      final config = SiteConfigDefaults.all.firstWhere(
        (c) => c.name == 'email_on_user_registered',
      );
      expect(config.value, 'true');
      expect(config.valueType, ConfigValueType.boolean);
    });

    test('email_on_webhook_disabled defaults to true', () {
      final config = SiteConfigDefaults.all.firstWhere(
        (c) => c.name == 'email_on_webhook_disabled',
      );
      expect(config.value, 'true');
      expect(config.valueType, ConfigValueType.boolean);
    });

    test('admin_notification_email defaults to empty string', () {
      final config = SiteConfigDefaults.all.firstWhere(
        (c) => c.name == 'admin_notification_email',
      );
      expect(config.value, '');
      expect(config.valueType, ConfigValueType.string);
    });
  });

  group('EmailService', () {
    late SqliteMetadataStore metadata;
    late EmailService emailService;

    setUp(() async {
      metadata = SqliteMetadataStore.open(':memory:');
      metadata.runMigrations();
      emailService = EmailService(metadata: metadata);
    });

    tearDown(() {
      metadata.close();
    });

    test('clearConfigCache resets cached config', () {
      // Just verify this doesn't throw
      emailService.clearConfigCache();
    });

    test('email not sent when SMTP not configured', () async {
      // With default config (not enabled), emails should not be sent
      // This test verifies the service doesn't throw when SMTP is not configured
      await emailService.onUserRegistered(
        email: 'test@example.com',
        name: 'Test User',
      );
      // Should complete without error
    });

    test('email not sent when notification type disabled', () async {
      // Set SMTP config but disable user registration emails
      await metadata.setConfig('smtp_host', 'smtp.test.com');
      await metadata.setConfig('smtp_from_address', 'test@test.com');
      await metadata.setConfig('email_notifications_enabled', 'true');
      await metadata.setConfig('email_on_user_registered', 'false');

      emailService.clearConfigCache();

      // This should not attempt to send because registration emails are disabled
      // (It will still fail the SMTP connection, but the check happens first)
      await emailService.onUserRegistered(
        email: 'test@example.com',
        name: 'Test User',
      );
    });

    test('email not sent when package publish notifications disabled',
        () async {
      await metadata.setConfig('smtp_host', 'smtp.test.com');
      await metadata.setConfig('smtp_from_address', 'test@test.com');
      await metadata.setConfig('email_notifications_enabled', 'true');
      await metadata.setConfig('email_on_package_published', 'false');

      emailService.clearConfigCache();

      await emailService.onPackagePublished(
        packageName: 'test_package',
        version: '1.0.0',
        publisherEmail: 'publisher@example.com',
      );
    });

    test('webhook disabled notification skipped when SMTP not configured',
        () async {
      // With default config (not enabled), emails should not be sent
      await emailService.onWebhookDisabled(
        webhookId: 'test-webhook-id',
        webhookUrl: 'https://example.com/webhook',
        reason: 'Test reason',
      );
      // Should complete without error
    });

    test('webhook disabled notification skipped when admin email not set',
        () async {
      await metadata.setConfig('smtp_host', 'smtp.test.com');
      await metadata.setConfig('smtp_from_address', 'test@test.com');
      await metadata.setConfig('email_notifications_enabled', 'true');
      await metadata.setConfig('email_on_webhook_disabled', 'true');
      // admin_notification_email not set

      emailService.clearConfigCache();

      await emailService.onWebhookDisabled(
        webhookId: 'test-webhook-id',
        webhookUrl: 'https://example.com/webhook',
        reason: 'Test reason',
      );
      // Should complete without error
    });

    test('webhook disabled notification skipped when disabled', () async {
      await metadata.setConfig('smtp_host', 'smtp.test.com');
      await metadata.setConfig('smtp_from_address', 'test@test.com');
      await metadata.setConfig('email_notifications_enabled', 'true');
      await metadata.setConfig('email_on_webhook_disabled', 'false');
      await metadata.setConfig('admin_notification_email', 'admin@test.com');

      emailService.clearConfigCache();

      await emailService.onWebhookDisabled(
        webhookId: 'test-webhook-id',
        webhookUrl: 'https://example.com/webhook',
        reason: 'Test reason',
      );
      // Should complete without error
    });
  });
}

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repub_model/repub_model.dart' as model;

import 'package:repub_admin/blocs/config/config_bloc.dart';
import 'package:repub_admin/blocs/config/config_event.dart';
import 'package:repub_admin/blocs/config/config_state.dart';
import 'package:repub_admin/models/site_config.dart';
import 'package:repub_admin/services/admin_api_client.dart';

// Mock classes
class MockAdminApiClient extends Mock implements AdminApiClient {}

void main() {
  group('ConfigBloc', () {
    late MockAdminApiClient mockApiClient;

    setUp(() {
      mockApiClient = MockAdminApiClient();
    });

    test('initial state is ConfigInitial', () {
      final bloc = ConfigBloc(apiClient: mockApiClient);
      expect(bloc.state, const ConfigInitial());
      bloc.close();
    });

    group('LoadConfig', () {
      final testConfigList = [
        model.SiteConfig(name: 'base_url', valueType: model.ConfigValueType.string, value: 'http://localhost:4920'),
        model.SiteConfig(name: 'listen_addr', valueType: model.ConfigValueType.string, value: '0.0.0.0:4920'),
        model.SiteConfig(name: 'require_download_auth', valueType: model.ConfigValueType.boolean, value: 'false'),
        model.SiteConfig(name: 'database_type', valueType: model.ConfigValueType.string, value: 'sqlite'),
        model.SiteConfig(name: 'storage_type', valueType: model.ConfigValueType.string, value: 'local'),
        model.SiteConfig(name: 'max_upload_size_mb', valueType: model.ConfigValueType.number, value: '100'),
        model.SiteConfig(name: 'allow_public_registration', valueType: model.ConfigValueType.boolean, value: 'true'),
      ];

      blocTest<ConfigBloc, ConfigState>(
        'emits [ConfigLoading, ConfigLoaded] when LoadConfig succeeds',
        build: () {
          when(() => mockApiClient.getConfig())
              .thenAnswer((_) async => testConfigList);
          return ConfigBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadConfig()),
        expect: () => [
          const ConfigLoading(),
          isA<ConfigLoaded>()
              .having((s) => s.config.baseUrl, 'baseUrl',
                  'http://localhost:4920')
              .having((s) => s.config.databaseType, 'databaseType', 'sqlite')
              .having((s) => s.config.storageType, 'storageType', 'local')
              .having((s) => s.config.requireDownloadAuth, 'requireDownloadAuth',
                  false)
              .having((s) => s.config.allowPublicRegistration,
                  'allowPublicRegistration', true),
        ],
      );

      blocTest<ConfigBloc, ConfigState>(
        'emits [ConfigLoading, ConfigError] when LoadConfig fails',
        build: () {
          when(() => mockApiClient.getConfig())
              .thenThrow(Exception('Network error'));
          return ConfigBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadConfig()),
        expect: () => [
          const ConfigLoading(),
          isA<ConfigError>()
              .having((s) => s.message, 'message', contains('Failed to load')),
        ],
      );

      blocTest<ConfigBloc, ConfigState>(
        'handles empty config list with defaults',
        build: () {
          when(() => mockApiClient.getConfig()).thenAnswer((_) async => <model.SiteConfig>[]);
          return ConfigBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadConfig()),
        expect: () => [
          const ConfigLoading(),
          isA<ConfigLoaded>()
              .having((s) => s.config.baseUrl, 'baseUrl',
                  'http://localhost:4920') // default
              .having((s) => s.config.maxUploadSizeMb, 'maxUploadSizeMb', 100), // default
        ],
      );
    });

    group('UpdateConfig', () {
      final testConfig = const SiteConfig(
        baseUrl: 'https://pub.example.com',
        listenAddr: '0.0.0.0:8080',
        requireDownloadAuth: true,
        databaseType: 'postgres',
        storageType: 's3',
        maxUploadSizeMb: 200,
        allowPublicRegistration: false,
      );

      blocTest<ConfigBloc, ConfigState>(
        'emits [ConfigUpdating, ConfigUpdateSuccess, ...] when update succeeds',
        build: () {
          when(() => mockApiClient.setConfig(any(), any()))
              .thenAnswer((_) async {});
          when(() => mockApiClient.getConfig()).thenAnswer((_) async => [
                model.SiteConfig(name: 'base_url', valueType: model.ConfigValueType.string, value: testConfig.baseUrl),
                model.SiteConfig(
                    name: 'listen_addr', valueType: model.ConfigValueType.string, value: testConfig.listenAddr),
              ]);
          return ConfigBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(UpdateConfig(testConfig)),
        expect: () => [
          ConfigUpdating(testConfig),
          isA<ConfigUpdateSuccess>()
              .having((s) => s.message, 'message',
                  contains('Configuration updated'))
              .having((s) => s.config.baseUrl, 'config baseUrl',
                  'https://pub.example.com'),
          const ConfigLoading(),
          isA<ConfigLoaded>(),
        ],
        verify: (_) {
          // Verify all config values were set
          verify(() =>
                  mockApiClient.setConfig('base_url', 'https://pub.example.com'))
              .called(1);
          verify(() => mockApiClient.setConfig('listen_addr', '0.0.0.0:8080'))
              .called(1);
          verify(() =>
                  mockApiClient.setConfig('require_download_auth', 'true'))
              .called(1);
          verify(() => mockApiClient.setConfig('database_type', 'postgres'))
              .called(1);
          verify(() => mockApiClient.setConfig('storage_type', 's3')).called(1);
          verify(() => mockApiClient.setConfig('max_upload_size_mb', '200'))
              .called(1);
          verify(() =>
                  mockApiClient.setConfig('allow_public_registration', 'false'))
              .called(1);
        },
      );

      blocTest<ConfigBloc, ConfigState>(
        'emits ConfigUpdateError when update fails',
        build: () {
          when(() => mockApiClient.setConfig(any(), any()))
              .thenThrow(AdminApiException(statusCode: 500, message: 'Error'));
          return ConfigBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(UpdateConfig(testConfig)),
        expect: () => [
          ConfigUpdating(testConfig),
          isA<ConfigUpdateError>()
              .having((s) => s.message, 'message', contains('Failed to update')),
        ],
      );

      blocTest<ConfigBloc, ConfigState>(
        'updates SMTP config when provided',
        build: () {
          when(() => mockApiClient.setConfig(any(), any()))
              .thenAnswer((_) async {});
          when(() => mockApiClient.getConfig()).thenAnswer((_) async => <model.SiteConfig>[]);
          return ConfigBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(UpdateConfig(testConfig.copyWith(
          smtpHost: 'smtp.example.com',
          smtpPort: 587,
          smtpFrom: 'noreply@example.com',
        ))),
        verify: (_) {
          verify(() => mockApiClient.setConfig('smtp_host', 'smtp.example.com'))
              .called(1);
          verify(() => mockApiClient.setConfig('smtp_port', '587')).called(1);
          verify(() =>
                  mockApiClient.setConfig('smtp_from', 'noreply@example.com'))
              .called(1);
        },
      );
    });

    group('UpdateConfigValue', () {
      final currentConfig = const SiteConfig(
        baseUrl: 'http://localhost:4920',
        listenAddr: '0.0.0.0:4920',
        requireDownloadAuth: false,
        databaseType: 'sqlite',
        storageType: 'local',
        maxUploadSizeMb: 100,
        allowPublicRegistration: true,
      );

      blocTest<ConfigBloc, ConfigState>(
        'updates single config value when in loaded state',
        build: () {
          when(() => mockApiClient.setConfig('max_upload_size_mb', '250'))
              .thenAnswer((_) async {});
          when(() => mockApiClient.getConfig()).thenAnswer((_) async => [
                model.SiteConfig(name: 'max_upload_size_mb', valueType: model.ConfigValueType.number, value: '250'),
              ]);
          return ConfigBloc(apiClient: mockApiClient);
        },
        seed: () => ConfigLoaded(currentConfig),
        act: (bloc) => bloc.add(
            const UpdateConfigValue('max_upload_size_mb', '250')),
        expect: () => [
          ConfigUpdating(currentConfig),
          isA<ConfigUpdateSuccess>()
              .having((s) => s.message, 'message',
                  contains('max_upload_size_mb')),
          const ConfigLoading(),
          isA<ConfigLoaded>(),
        ],
      );

      blocTest<ConfigBloc, ConfigState>(
        'emits error when single value update fails',
        build: () {
          when(() => mockApiClient.setConfig(any(), any()))
              .thenThrow(AdminApiException(statusCode: 400, message: 'Invalid'));
          return ConfigBloc(apiClient: mockApiClient);
        },
        seed: () => ConfigLoaded(currentConfig),
        act: (bloc) =>
            bloc.add(const UpdateConfigValue('invalid_key', 'x')),
        expect: () => [
          ConfigUpdating(currentConfig),
          isA<ConfigUpdateError>()
              .having((s) => s.message, 'message', contains('Failed')),
        ],
      );

      blocTest<ConfigBloc, ConfigState>(
        'does nothing when not in loaded state',
        build: () {
          return ConfigBloc(apiClient: mockApiClient);
        },
        act: (bloc) =>
            bloc.add(const UpdateConfigValue('key', 'value')),
        expect: () => [], // No state changes
      );
    });
  });
}

import 'package:repub_auth/repub_auth.dart';
import 'package:repub_model/repub_model.dart';
import 'package:test/test.dart';

void main() {
  group('Scope Checking Functions', () {
    late AuthToken adminToken;
    late AuthToken publishAllToken;
    late AuthToken publishPkgToken;
    late AuthToken readAllToken;
    late AuthToken noScopesToken;

    setUp(() {
      final now = DateTime.now();

      adminToken = AuthToken(
        tokenHash: 'admin_hash',
        userId: 'user1',
        label: 'Admin Token',
        scopes: ['admin'],
        createdAt: now,
      );

      publishAllToken = AuthToken(
        tokenHash: 'publish_all_hash',
        userId: 'user2',
        label: 'Publish All Token',
        scopes: ['publish:all'],
        createdAt: now,
      );

      publishPkgToken = AuthToken(
        tokenHash: 'publish_pkg_hash',
        userId: 'user3',
        label: 'Publish Package Token',
        scopes: ['publish:pkg:my_package'],
        createdAt: now,
      );

      readAllToken = AuthToken(
        tokenHash: 'read_all_hash',
        userId: 'user4',
        label: 'Read All Token',
        scopes: ['read:all'],
        createdAt: now,
      );

      noScopesToken = AuthToken(
        tokenHash: 'no_scopes_hash',
        userId: 'user5',
        label: 'No Scopes Token',
        scopes: [],
        createdAt: now,
      );
    });

    group('hasScope', () {
      test('returns true when token has exact scope', () {
        expect(hasScope(adminToken, 'admin'), isTrue);
        expect(hasScope(publishAllToken, 'publish:all'), isTrue);
        expect(hasScope(readAllToken, 'read:all'), isTrue);
      });

      test('returns false when token lacks scope', () {
        expect(hasScope(publishAllToken, 'admin'), isFalse);
        expect(hasScope(readAllToken, 'publish:all'), isFalse);
        expect(hasScope(noScopesToken, 'admin'), isFalse);
      });
    });

    group('hasAdminScope', () {
      test('returns true for token with admin scope', () {
        expect(hasAdminScope(adminToken), isTrue);
      });

      test('returns false for token without admin scope', () {
        expect(hasAdminScope(publishAllToken), isFalse);
        expect(hasAdminScope(readAllToken), isFalse);
        expect(hasAdminScope(noScopesToken), isFalse);
      });
    });

    group('canPublishAll', () {
      test('returns true for admin token', () {
        expect(canPublishAll(adminToken), isTrue);
      });

      test('returns true for publish:all token', () {
        expect(canPublishAll(publishAllToken), isTrue);
      });

      test('returns false for other tokens', () {
        expect(canPublishAll(publishPkgToken), isFalse);
        expect(canPublishAll(readAllToken), isFalse);
        expect(canPublishAll(noScopesToken), isFalse);
      });
    });

    group('canPublishPackage', () {
      test('returns true for admin token', () {
        expect(canPublishPackage(adminToken, 'any_package'), isTrue);
        expect(canPublishPackage(adminToken, 'another_package'), isTrue);
      });

      test('returns true for publish:all token', () {
        expect(canPublishPackage(publishAllToken, 'any_package'), isTrue);
        expect(canPublishPackage(publishAllToken, 'another_package'), isTrue);
      });

      test('returns true for specific package token when package matches', () {
        expect(canPublishPackage(publishPkgToken, 'my_package'), isTrue);
      });

      test(
          'returns false for specific package token when package does not match',
          () {
        expect(canPublishPackage(publishPkgToken, 'other_package'), isFalse);
      });

      test('returns false for tokens without publish scopes', () {
        expect(canPublishPackage(readAllToken, 'any_package'), isFalse);
        expect(canPublishPackage(noScopesToken, 'any_package'), isFalse);
      });
    });

    group('canRead', () {
      test('returns true for admin token', () {
        expect(canRead(adminToken), isTrue);
      });

      test('returns true for read:all token', () {
        expect(canRead(readAllToken), isTrue);
      });

      test('returns false for tokens without read scopes', () {
        expect(canRead(publishAllToken), isFalse);
        expect(canRead(publishPkgToken), isFalse);
        expect(canRead(noScopesToken), isFalse);
      });
    });

    group('requireScope', () {
      test('returns null when token has required scope', () {
        expect(requireScope(adminToken, 'admin'), isNull);
        expect(requireScope(publishAllToken, 'publish:all'), isNull);
      });

      test('returns 403 response when token lacks required scope', () {
        final response = requireScope(publishAllToken, 'admin');
        expect(response, isNotNull);
        expect(response!.statusCode, equals(403));
        expect(response.headers['content-type'], equals('text/plain'));
      });
    });

    group('requireAdminScope', () {
      test('returns null when token has admin scope', () {
        expect(requireAdminScope(adminToken), isNull);
      });

      test('returns 403 response when token lacks admin scope', () {
        final response = requireAdminScope(publishAllToken);
        expect(response, isNotNull);
        expect(response!.statusCode, equals(403));
      });
    });

    group('requirePackagePublishScope', () {
      test('returns null when admin token', () {
        expect(requirePackagePublishScope(adminToken, 'any_package'), isNull);
      });

      test('returns null when publish:all token', () {
        expect(
            requirePackagePublishScope(publishAllToken, 'any_package'), isNull);
      });

      test('returns null when specific package token matches', () {
        expect(
            requirePackagePublishScope(publishPkgToken, 'my_package'), isNull);
      });

      test('returns 403 when specific package token does not match', () {
        final response =
            requirePackagePublishScope(publishPkgToken, 'other_package');
        expect(response, isNotNull);
        expect(response!.statusCode, equals(403));
      });

      test('returns 403 when token has no publish scopes', () {
        final response =
            requirePackagePublishScope(readAllToken, 'any_package');
        expect(response, isNotNull);
        expect(response!.statusCode, equals(403));
      });
    });

    group('requireReadScope', () {
      test('returns null when token has admin scope', () {
        expect(requireReadScope(adminToken), isNull);
      });

      test('returns null when token has read:all scope', () {
        expect(requireReadScope(readAllToken), isNull);
      });

      test('returns 403 when token lacks read scopes', () {
        final response = requireReadScope(publishAllToken);
        expect(response, isNotNull);
        expect(response!.statusCode, equals(403));
      });
    });

    group('Multiple Scopes', () {
      test('token with multiple scopes can access all', () {
        final multiScopeToken = AuthToken(
          tokenHash: 'multi_hash',
          userId: 'user6',
          label: 'Multi Scope Token',
          scopes: ['publish:all', 'read:all'],
          createdAt: DateTime.now(),
        );

        expect(canPublishAll(multiScopeToken), isTrue);
        expect(canRead(multiScopeToken), isTrue);
        expect(hasAdminScope(multiScopeToken), isFalse);
      });

      test('token with package-specific scopes for multiple packages', () {
        final multiPkgToken = AuthToken(
          tokenHash: 'multi_pkg_hash',
          userId: 'user7',
          label: 'Multi Package Token',
          scopes: ['publish:pkg:package_a', 'publish:pkg:package_b'],
          createdAt: DateTime.now(),
        );

        expect(canPublishPackage(multiPkgToken, 'package_a'), isTrue);
        expect(canPublishPackage(multiPkgToken, 'package_b'), isTrue);
        expect(canPublishPackage(multiPkgToken, 'package_c'), isFalse);
      });
    });

    group('Edge Cases', () {
      test('empty scopes list means no permissions', () {
        expect(hasAdminScope(noScopesToken), isFalse);
        expect(canPublishAll(noScopesToken), isFalse);
        expect(canPublishPackage(noScopesToken, 'any_package'), isFalse);
        expect(canRead(noScopesToken), isFalse);
      });

      test('scope matching is exact (no partial matches)', () {
        final partialToken = AuthToken(
          tokenHash: 'partial_hash',
          userId: 'user8',
          label: 'Partial Token',
          scopes: ['publish:pkg:my'],
          createdAt: DateTime.now(),
        );

        expect(canPublishPackage(partialToken, 'my'), isTrue);
        expect(canPublishPackage(partialToken, 'my_package'), isFalse);
      });

      test('admin scope grants all permissions', () {
        expect(hasAdminScope(adminToken), isTrue);
        expect(canPublishAll(adminToken), isTrue);
        expect(canPublishPackage(adminToken, 'any_package'), isTrue);
        expect(canRead(adminToken), isTrue);
        expect(requireAdminScope(adminToken), isNull);
        expect(requirePackagePublishScope(adminToken, 'any_package'), isNull);
        expect(requireReadScope(adminToken), isNull);
      });
    });
  });
}

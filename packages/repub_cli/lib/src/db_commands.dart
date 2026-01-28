import 'dart:io';
import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:repub_auth/repub_auth.dart';

/// Handle database reset command.
Future<void> dbResetCommand(List<String> args) async {
  final config = Config.fromEnv();

  // Check for confirmation flag
  final force = args.contains('--force') || args.contains('-f');

  if (!force) {
    print('');
    print('⚠️  WARNING: This will DROP ALL TABLES and DELETE ALL DATA!');
    print('');
    print('This action will:');
    print('  • Drop all existing tables');
    print('  • Recreate the database schema');
    print('  • Optionally seed with sample data');
    print('');
    stdout.write('Are you sure you want to continue? (yes/no): ');
    final response = stdin.readLineSync()?.toLowerCase().trim();

    if (response != 'yes') {
      print('Aborted.');
      return;
    }
  }

  print('');
  print('Database type: ${config.databaseType.name}');
  print('Connecting to database...');

  final metadata = await MetadataStore.create(config);

  print('Dropping all tables...');
  await metadata.dropAllTables();

  print('Running migrations...');
  final count = await metadata.runMigrations();
  print('Applied $count migration(s)');

  // Ask about seed data
  final shouldSeed = args.contains('--seed') ||
      args.contains('-s') ||
      (!force &&
          _promptYesNo('Do you want to seed with sample data?',
              defaultYes: true));

  if (shouldSeed) {
    print('Seeding database...');
    await _seedDatabase(metadata, config);
    print('✅ Database seeded successfully');
  }

  await metadata.close();
  print('');
  print('✅ Database reset complete');
}

/// Seed the database with sample data.
Future<void> _seedDatabase(MetadataStore metadata, Config config) async {
  // Create admin user
  print('  Creating admin user (username: admin, password: admin)...');
  final adminPasswordHash = hashPassword('admin');
  await metadata.createAdminUser(
    username: 'admin',
    passwordHash: adminPasswordHash,
  );

  // Create a sample user
  print('  Creating sample user (user@example.com)...');
  final userId = await metadata.createUser(email: 'user@example.com');

  // Create sample auth token for the user
  print('  Creating sample API token...');
  final token = await metadata.createToken(
    userId: userId,
    label: 'Development Token',
    scopes: ['publish:all', 'read:all'],
  );
  print('    Token: $token');
  print('    User: user@example.com');
  print('    Scopes: publish:all, read:all');

  // Create sample packages
  print('  Creating sample packages...');
  await _createSamplePackage(
    metadata,
    name: 'hello_world',
    version: '1.0.0',
    description: 'A simple hello world package',
  );

  await _createSamplePackage(
    metadata,
    name: 'sample_utils',
    version: '0.1.0',
    description: 'Sample utility functions',
  );

  await _createSamplePackage(
    metadata,
    name: 'demo_package',
    version: '2.5.3',
    description: 'Demo package for testing',
  );
}

/// Create a sample package.
Future<void> _createSamplePackage(
  MetadataStore metadata, {
  required String name,
  required String version,
  required String description,
}) async {
  final pubspec = {
    'name': name,
    'version': version,
    'description': description,
    'environment': {
      'sdk': '>=3.0.0 <4.0.0',
    },
  };

  await metadata.upsertPackageVersion(
    packageName: name,
    version: version,
    pubspec: pubspec,
    archiveKey: 'hosted-packages/$name/$version/sample.tar.gz',
    archiveSha256: 'sample_sha256_${name}_$version',
  );
}

/// Prompt for yes/no input.
bool _promptYesNo(String message, {bool defaultYes = false}) {
  final defaultText = defaultYes ? 'Y/n' : 'y/N';
  stdout.write('$message ($defaultText): ');
  final response = stdin.readLineSync()?.toLowerCase().trim();

  if (response == null || response.isEmpty) {
    return defaultYes;
  }

  return response == 'y' || response == 'yes';
}

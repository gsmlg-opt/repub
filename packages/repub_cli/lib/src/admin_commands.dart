import 'package:repub_auth/repub_auth.dart';
import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';

/// Admin user management commands (CLI-only).
Future<void> adminCommands(List<String> args, Config config) async {
  if (args.isEmpty) {
    _printUsage();
    return;
  }

  final command = args[0];
  final commandArgs = args.skip(1).toList();

  final metadata = await MetadataStore.create(config);

  try {
    switch (command) {
      case 'create':
        await _createAdmin(metadata, commandArgs);
        break;
      case 'list':
        await _listAdmins(metadata);
        break;
      case 'reset-password':
        await _resetPassword(metadata, commandArgs);
        break;
      case 'activate':
        await _activateAdmin(metadata, commandArgs);
        break;
      case 'deactivate':
        await _deactivateAdmin(metadata, commandArgs);
        break;
      case 'delete':
        await _deleteAdmin(metadata, commandArgs);
        break;
      default:
        Logger.error('Unknown admin command',
            component: 'cli', metadata: {'command': command});
        print('Unknown admin command: $command');
        _printUsage();
    }
  } finally {
    await metadata.close();
  }
}

void _printUsage() {
  print('''
Admin user management commands:

  create <username> <password> [name]  Create a new admin user
  list                                  List all admin users
  reset-password <username> <password>  Reset admin password
  activate <username>                   Activate an admin user
  deactivate <username>                 Deactivate an admin user
  delete <username>                     Delete an admin user

Examples:
  repub_cli admin create admin mypassword "Admin User"
  repub_cli admin list
  repub_cli admin reset-password admin newpassword
  repub_cli admin deactivate admin
  repub_cli admin delete admin
''');
}

Future<void> _createAdmin(MetadataStore metadata, List<String> args) async {
  if (args.length < 2) {
    print('Usage: admin create <username> <password> [name]');
    return;
  }

  final username = args[0];
  final password = args[1];
  final name = args.length > 2 ? args[2] : null;

  // Validate username
  if (username.isEmpty || username.length < 3) {
    Logger.error('Invalid username',
        component: 'cli',
        metadata: {'reason': 'Username must be at least 3 characters'});
    print('Error: Username must be at least 3 characters long');
    return;
  }

  // Validate password
  if (password.length < 8) {
    Logger.error('Invalid password',
        component: 'cli',
        metadata: {'reason': 'Password must be at least 8 characters'});
    print('Error: Password must be at least 8 characters long');
    return;
  }

  // Check if username already exists
  final existing = await metadata.getAdminUserByUsername(username);
  if (existing != null) {
    Logger.error('Admin user already exists',
        component: 'cli', metadata: {'username': username});
    print('Error: Admin user "$username" already exists');
    return;
  }

  // Hash the password
  final passwordHash = hashPassword(password);

  // Create admin user
  final id = await metadata.createAdminUser(
    username: username,
    passwordHash: passwordHash,
    name: name,
  );

  print('Admin user created successfully:');
  print('  ID: $id');
  print('  Username: $username');
  if (name != null) {
    print('  Name: $name');
  }
}

Future<void> _listAdmins(MetadataStore metadata) async {
  final admins = await metadata.listAdminUsers(limit: 100);

  if (admins.isEmpty) {
    print('No admin users found');
    return;
  }

  print('Admin users:');
  print('');
  for (final admin in admins) {
    final status = admin.isActive ? 'active' : 'inactive';
    print('  ${admin.username} ($status)');
    print('    ID: ${admin.id}');
    if (admin.name != null) {
      print('    Name: ${admin.name}');
    }
    print('    Created: ${admin.createdAt.toLocal()}');
    if (admin.lastLoginAt != null) {
      print('    Last login: ${admin.lastLoginAt!.toLocal()}');
    }
    print('');
  }
  print('Total: ${admins.length} admin user(s)');
}

Future<void> _resetPassword(MetadataStore metadata, List<String> args) async {
  if (args.length < 2) {
    print('Usage: admin reset-password <username> <new-password>');
    return;
  }

  final username = args[0];
  final newPassword = args[1];

  // Find admin user
  final admin = await metadata.getAdminUserByUsername(username);
  if (admin == null) {
    Logger.error('Admin user not found',
        component: 'cli', metadata: {'username': username});
    print('Error: Admin user "$username" not found');
    return;
  }

  // Hash the new password
  final passwordHash = hashPassword(newPassword);

  // Update password
  final updated = await metadata.updateAdminUser(
    admin.id,
    passwordHash: passwordHash,
  );

  if (updated) {
    print('Password reset successfully for admin user "$username"');
  } else {
    Logger.error('Failed to reset password',
        component: 'cli', metadata: {'username': username});
    print('Error: Failed to reset password');
  }
}

Future<void> _activateAdmin(MetadataStore metadata, List<String> args) async {
  if (args.isEmpty) {
    print('Usage: admin activate <username>');
    return;
  }

  final username = args[0];

  // Find admin user
  final admin = await metadata.getAdminUserByUsername(username);
  if (admin == null) {
    Logger.error('Admin user not found',
        component: 'cli', metadata: {'username': username});
    print('Error: Admin user "$username" not found');
    return;
  }

  if (admin.isActive) {
    print('Admin user "$username" is already active');
    return;
  }

  // Activate
  final updated = await metadata.updateAdminUser(admin.id, isActive: true);

  if (updated) {
    print('Admin user "$username" activated successfully');
  } else {
    Logger.error('Failed to activate admin user',
        component: 'cli', metadata: {'username': username});
    print('Error: Failed to activate admin user');
  }
}

Future<void> _deactivateAdmin(MetadataStore metadata, List<String> args) async {
  if (args.isEmpty) {
    print('Usage: admin deactivate <username>');
    return;
  }

  final username = args[0];

  // Find admin user
  final admin = await metadata.getAdminUserByUsername(username);
  if (admin == null) {
    Logger.error('Admin user not found',
        component: 'cli', metadata: {'username': username});
    print('Error: Admin user "$username" not found');
    return;
  }

  if (!admin.isActive) {
    print('Admin user "$username" is already inactive');
    return;
  }

  // Deactivate
  final updated = await metadata.updateAdminUser(admin.id, isActive: false);

  if (updated) {
    print('Admin user "$username" deactivated successfully');
    print('Note: Existing sessions will remain valid until expiry');
  } else {
    Logger.error('Failed to deactivate admin user',
        component: 'cli', metadata: {'username': username});
    print('Error: Failed to deactivate admin user');
  }
}

Future<void> _deleteAdmin(MetadataStore metadata, List<String> args) async {
  if (args.isEmpty) {
    print('Usage: admin delete <username>');
    return;
  }

  final username = args[0];

  // Find admin user
  final admin = await metadata.getAdminUserByUsername(username);
  if (admin == null) {
    Logger.error('Admin user not found',
        component: 'cli', metadata: {'username': username});
    print('Error: Admin user "$username" not found');
    return;
  }

  // Delete
  final deleted = await metadata.deleteAdminUser(admin.id);

  if (deleted) {
    print('Admin user "$username" deleted successfully');
    print('All associated sessions have been removed');
  } else {
    Logger.error('Failed to delete admin user',
        component: 'cli', metadata: {'username': username});
    print('Error: Failed to delete admin user');
  }
}

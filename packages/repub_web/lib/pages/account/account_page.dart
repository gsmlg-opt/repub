import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';

import '../../src/components/layout.dart';
import '../../src/services/auth_api_client.dart';

/// Account page for viewing and managing user profile.
@client
class AccountPage extends StatefulComponent {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _loading = true;
  String? _error;
  UserData? _user;

  // Edit mode
  bool _editing = false;
  String _name = '';
  String _currentPassword = '';
  String _newPassword = '';
  String _confirmPassword = '';
  bool _saving = false;
  String? _saveError;
  String? _saveSuccess;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = AuthApiClient();
    try {
      final user = await client.getCurrentUser();
      if (user == null) {
        // Not logged in, redirect to login
        Router.of(context).push('/login');
        return;
      }
      setState(() {
        _user = user;
        _name = user.name ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e is AuthApiException ? e.message : 'Failed to load user';
        _loading = false;
      });
    } finally {
      client.dispose();
    }
  }

  Future<void> _handleSave() async {
    setState(() {
      _saving = true;
      _saveError = null;
      _saveSuccess = null;
    });

    // Validate password change
    if (_newPassword.isNotEmpty) {
      if (_currentPassword.isEmpty) {
        setState(() {
          _saveError = 'Current password is required to change password';
          _saving = false;
        });
        return;
      }
      if (_newPassword.length < 8) {
        setState(() {
          _saveError = 'New password must be at least 8 characters';
          _saving = false;
        });
        return;
      }
      if (_newPassword != _confirmPassword) {
        setState(() {
          _saveError = 'New passwords do not match';
          _saving = false;
        });
        return;
      }
    }

    final client = AuthApiClient();
    try {
      final user = await client.updateProfile(
        name: _name.isNotEmpty ? _name : null,
        password: _newPassword.isNotEmpty ? _newPassword : null,
        currentPassword: _currentPassword.isNotEmpty ? _currentPassword : null,
      );
      setState(() {
        _user = user;
        _editing = false;
        _currentPassword = '';
        _newPassword = '';
        _confirmPassword = '';
        _saveSuccess = 'Profile updated successfully';
        _saving = false;
      });
    } on AuthApiException catch (e) {
      setState(() {
        _saveError = e.message;
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _saveError = 'Failed to save changes';
        _saving = false;
      });
    } finally {
      client.dispose();
    }
  }

  Future<void> _handleLogout() async {
    final client = AuthApiClient();
    try {
      await client.logout();
    } finally {
      client.dispose();
    }
    Router.of(context).push('/');
  }

  @override
  Component build(BuildContext context) {
    return buildLayout(
      children: [
        div(
          classes: 'max-w-2xl mx-auto',
          [
            // Header
            div(
              classes: 'flex items-center justify-between mb-8',
              [
                h1(
                  classes: 'text-3xl font-bold text-gray-900',
                  [Component.text('Account Settings')],
                ),
                if (_user != null)
                  button(
                    type: ButtonType.button,
                    classes: 'px-4 py-2 text-gray-600 hover:text-gray-900',
                    events: {'click': (_) => _handleLogout()},
                    [Component.text('Sign Out')],
                  ),
              ],
            ),
            if (_loading)
              _buildLoadingState()
            else if (_error != null)
              _buildErrorState(_error!)
            else if (_user != null)
              _buildContent(_user!),
          ],
        ),
      ],
    );
  }

  Component _buildLoadingState() {
    return div(
      classes: 'bg-white rounded-lg shadow p-6 animate-pulse',
      [
        div(classes: 'h-6 bg-gray-200 rounded w-1/3 mb-4', []),
        div(classes: 'h-4 bg-gray-200 rounded w-2/3 mb-2', []),
        div(classes: 'h-4 bg-gray-200 rounded w-1/2', []),
      ],
    );
  }

  Component _buildErrorState(String error) {
    return div(
      classes: 'bg-white rounded-lg shadow p-6 text-center',
      [
        p(classes: 'text-red-600 mb-4', [Component.text(error)]),
        button(
          type: ButtonType.button,
          classes:
              'px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700',
          events: {'click': (_) => _loadUser()},
          [Component.text('Try again')],
        ),
      ],
    );
  }

  Component _buildContent(UserData user) {
    return Component.fragment([
      // Success message
      if (_saveSuccess != null)
        div(
          classes:
              'mb-4 p-3 bg-green-50 border border-green-200 rounded-lg text-green-700 text-sm',
          [Component.text(_saveSuccess!)],
        ),
      // Profile card
      div(
        classes: 'bg-white rounded-lg shadow p-6 mb-6',
        [
          div(
            classes: 'flex items-center justify-between mb-4',
            [
              h2(
                classes: 'text-lg font-semibold text-gray-900',
                [Component.text('Profile')],
              ),
              if (!_editing)
                button(
                  type: ButtonType.button,
                  classes:
                      'text-blue-600 hover:text-blue-800 text-sm font-medium',
                  events: {'click': (_) => setState(() => _editing = true)},
                  [Component.text('Edit')],
                ),
            ],
          ),
          if (_editing) _buildEditForm(user) else _buildProfileView(user),
        ],
      ),
      // Quick actions
      div(
        classes: 'bg-white rounded-lg shadow p-6',
        [
          h2(
            classes: 'text-lg font-semibold text-gray-900 mb-4',
            [Component.text('Quick Actions')],
          ),
          div(
            classes: 'grid gap-4 md:grid-cols-2',
            [
              _actionCard(
                'API Tokens',
                'Manage your API tokens for publishing',
                '/account/tokens',
                'bg-blue-50 border-blue-200 hover:bg-blue-100',
              ),
              _actionCard(
                'My Packages',
                'View packages you own',
                '/',
                'bg-green-50 border-green-200 hover:bg-green-100',
              ),
            ],
          ),
        ],
      ),
    ]);
  }

  Component _buildProfileView(UserData user) {
    return div(
      classes: 'space-y-4',
      [
        _infoRow('Email', user.email),
        _infoRow('Name', user.name ?? 'Not set'),
        _infoRow('Member since', _formatDate(user.createdAt)),
        if (user.lastLoginAt != null)
          _infoRow('Last login', _formatDate(user.lastLoginAt!)),
      ],
    );
  }

  Component _buildEditForm(UserData user) {
    return div([
      if (_saveError != null)
        div(
          classes:
              'mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm',
          [Component.text(_saveError!)],
        ),
      // Name field
      div(
        classes: 'mb-4',
        [
          label(
            classes: 'block text-sm font-medium text-gray-700 mb-1',
            [Component.text('Name')],
          ),
          input(
            type: InputType.text,
            classes:
                'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
            attributes: {'value': _name, 'placeholder': 'Your name'},
            events: {
              'input': (e) {
                final target = e.target;
                if (target != null) {
                  _name = (target as dynamic).value as String;
                }
              },
            },
          ),
        ],
      ),
      // Change password section
      div(
        classes: 'border-t pt-4 mt-4',
        [
          h3(
            classes: 'text-sm font-medium text-gray-900 mb-3',
            [Component.text('Change Password (optional)')],
          ),
          div(
            classes: 'mb-4',
            [
              label(
                classes: 'block text-sm font-medium text-gray-700 mb-1',
                [Component.text('Current Password')],
              ),
              input(
                type: InputType.password,
                classes:
                    'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
                attributes: {'value': _currentPassword},
                events: {
                  'input': (e) {
                    final target = e.target;
                    if (target != null) {
                      _currentPassword = (target as dynamic).value as String;
                    }
                  },
                },
              ),
            ],
          ),
          div(
            classes: 'mb-4',
            [
              label(
                classes: 'block text-sm font-medium text-gray-700 mb-1',
                [Component.text('New Password')],
              ),
              input(
                type: InputType.password,
                classes:
                    'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
                attributes: {
                  'value': _newPassword,
                  'placeholder': 'At least 8 characters'
                },
                events: {
                  'input': (e) {
                    final target = e.target;
                    if (target != null) {
                      _newPassword = (target as dynamic).value as String;
                    }
                  },
                },
              ),
            ],
          ),
          div(
            classes: 'mb-4',
            [
              label(
                classes: 'block text-sm font-medium text-gray-700 mb-1',
                [Component.text('Confirm New Password')],
              ),
              input(
                type: InputType.password,
                classes:
                    'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
                attributes: {'value': _confirmPassword},
                events: {
                  'input': (e) {
                    final target = e.target;
                    if (target != null) {
                      _confirmPassword = (target as dynamic).value as String;
                    }
                  },
                },
              ),
            ],
          ),
        ],
      ),
      // Buttons
      div(
        classes: 'flex justify-end space-x-3 mt-4',
        [
          button(
            type: ButtonType.button,
            classes: 'px-4 py-2 text-gray-600 hover:text-gray-900',
            events: {
              'click': (_) => setState(() {
                    _editing = false;
                    _name = user.name ?? '';
                    _currentPassword = '';
                    _newPassword = '';
                    _confirmPassword = '';
                    _saveError = null;
                  })
            },
            [Component.text('Cancel')],
          ),
          button(
            type: ButtonType.button,
            classes:
                'px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50',
            attributes: _saving ? {'disabled': 'true'} : {},
            events: {'click': (_) => _handleSave()},
            [Component.text(_saving ? 'Saving...' : 'Save Changes')],
          ),
        ],
      ),
    ]);
  }

  Component _infoRow(String label, String value) {
    return div(
      classes:
          'flex items-center justify-between py-2 border-b border-gray-100 last:border-0',
      [
        span(classes: 'text-gray-500 text-sm', [Component.text(label)]),
        span(classes: 'text-gray-900 font-medium', [Component.text(value)]),
      ],
    );
  }

  Component _actionCard(
      String title, String description, String href, String colorClasses) {
    return a(
      href: href,
      classes: 'block p-4 border rounded-lg transition-colors $colorClasses',
      [
        h3(classes: 'font-medium text-gray-900', [Component.text(title)]),
        p(classes: 'text-sm text-gray-600 mt-1', [Component.text(description)]),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

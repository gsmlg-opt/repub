import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';

import '../../src/components/layout.dart';
import '../../src/services/auth_api_client.dart';

/// Register page for new user registration.
@client
class RegisterPage extends StatefulComponent {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  String _email = '';
  String _password = '';
  String _confirmPassword = '';
  String _name = '';
  bool _loading = false;
  String? _error;

  Future<void> _handleRegister() async {
    if (_email.isEmpty || _password.isEmpty) {
      setState(() => _error = 'Please enter email and password');
      return;
    }

    if (_password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }

    if (_password != _confirmPassword) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final client = AuthApiClient();
    try {
      await client.register(
        email: _email,
        password: _password,
        name: _name.isNotEmpty ? _name : null,
      );
      // Navigate to account page on success
      Router.of(context).push('/account');
    } on AuthApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e, stackTrace) {
      // Log detailed error for debugging
      print('Registration error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _error = 'Error: ${e.toString()}';
        _loading = false;
      });
    } finally {
      client.dispose();
    }
  }

  @override
  Component build(BuildContext context) {
    return buildLayout(
      children: [
        div(
          classes: 'max-w-md mx-auto',
          [
            // Header
            div(
              classes: 'text-center mb-8',
              [
                h1(
                  classes: 'text-3xl font-bold text-gray-900',
                  [Component.text('Create Account')],
                ),
                p(
                  classes: 'mt-2 text-gray-600',
                  [Component.text('Register to publish and manage packages')],
                ),
              ],
            ),
            // Form card
            div(
              classes: 'bg-white rounded-lg shadow p-6',
              [
                if (_error != null)
                  div(
                    classes:
                        'mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm',
                    [Component.text(_error!)],
                  ),
                // Name field (optional)
                div(
                  classes: 'mb-4',
                  [
                    label(
                      classes: 'block text-sm font-medium text-gray-700 mb-1',
                      attributes: {'for': 'name'},
                      [Component.text('Name (optional)')],
                    ),
                    input(
                      id: 'name',
                      type: InputType.text,
                      classes:
                          'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
                      attributes: {
                        'placeholder': 'Your name',
                        'value': _name,
                      },
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
                // Email field
                div(
                  classes: 'mb-4',
                  [
                    label(
                      classes: 'block text-sm font-medium text-gray-700 mb-1',
                      attributes: {'for': 'email'},
                      [Component.text('Email')],
                    ),
                    input(
                      id: 'email',
                      type: InputType.email,
                      classes:
                          'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
                      attributes: {
                        'placeholder': 'you@example.com',
                        'value': _email,
                      },
                      events: {
                        'input': (e) {
                          final target = e.target;
                          if (target != null) {
                            _email = (target as dynamic).value as String;
                          }
                        },
                      },
                    ),
                  ],
                ),
                // Password field
                div(
                  classes: 'mb-4',
                  [
                    label(
                      classes: 'block text-sm font-medium text-gray-700 mb-1',
                      attributes: {'for': 'password'},
                      [Component.text('Password')],
                    ),
                    input(
                      id: 'password',
                      type: InputType.password,
                      classes:
                          'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
                      attributes: {
                        'placeholder': 'At least 8 characters',
                        'value': _password,
                      },
                      events: {
                        'input': (e) {
                          final target = e.target;
                          if (target != null) {
                            _password = (target as dynamic).value as String;
                          }
                        },
                      },
                    ),
                  ],
                ),
                // Confirm password field
                div(
                  classes: 'mb-6',
                  [
                    label(
                      classes: 'block text-sm font-medium text-gray-700 mb-1',
                      attributes: {'for': 'confirmPassword'},
                      [Component.text('Confirm Password')],
                    ),
                    input(
                      id: 'confirmPassword',
                      type: InputType.password,
                      classes:
                          'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
                      attributes: {
                        'placeholder': 'Confirm your password',
                        'value': _confirmPassword,
                      },
                      events: {
                        'input': (e) {
                          final target = e.target;
                          if (target != null) {
                            _confirmPassword =
                                (target as dynamic).value as String;
                          }
                        },
                        'keypress': (e) {
                          if ((e as dynamic).key == 'Enter') {
                            _handleRegister();
                          }
                        },
                      },
                    ),
                  ],
                ),
                // Submit button
                button(
                  type: ButtonType.button,
                  classes:
                      'w-full py-2 px-4 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed',
                  attributes: _loading ? {'disabled': 'true'} : {},
                  events: {'click': (_) => _handleRegister()},
                  [
                    Component.text(
                        _loading ? 'Creating account...' : 'Create Account')
                  ],
                ),
                // Login link
                div(
                  classes: 'mt-4 text-center text-sm text-gray-600',
                  [
                    Component.text('Already have an account? '),
                    a(
                      href: '/login',
                      classes: 'text-blue-600 hover:text-blue-800 font-medium',
                      [Component.text('Sign in')],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

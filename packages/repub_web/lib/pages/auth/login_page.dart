import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:web/web.dart' as web;

import '../../src/components/layout.dart';
import '../../src/services/auth_api_client.dart';

/// Login page for user authentication.
@client
class LoginPage extends StatefulComponent {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String _email = '';
  String _password = '';
  bool _loading = false;
  String? _error;
  bool _isSecureContext = true;

  @override
  void initState() {
    super.initState();
    // Check if we're in a secure context (HTTPS or localhost)
    _isSecureContext = web.window.isSecureContext;
    if (!_isSecureContext) {
      _error =
          'Login requires a secure context (HTTPS or localhost). This page must be accessed over HTTPS for password encryption to work.';
    }
  }

  Future<void> _handleLogin() async {
    if (_email.isEmpty || _password.isEmpty) {
      setState(() => _error = 'Please enter email and password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final client = AuthApiClient();
    try {
      await client.login(email: _email, password: _password);
      // Navigate to account page on success
      Router.of(context).push('/account');
    } on AuthApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'An unexpected error occurred';
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
                  [Component.text('Sign In')],
                ),
                p(
                  classes: 'mt-2 text-gray-600',
                  [
                    Component.text('Sign in to manage your packages and tokens')
                  ],
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
                  classes: 'mb-6',
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
                        'placeholder': 'Enter your password',
                        'value': _password,
                      },
                      events: {
                        'input': (e) {
                          final target = e.target;
                          if (target != null) {
                            _password = (target as dynamic).value as String;
                          }
                        },
                        'keypress': (e) {
                          if ((e as dynamic).key == 'Enter') {
                            _handleLogin();
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
                  attributes: (_loading || !_isSecureContext)
                      ? {'disabled': 'true'}
                      : {},
                  events: {'click': (_) => _handleLogin()},
                  [Component.text(_loading ? 'Signing in...' : 'Sign In')],
                ),
                // Register link
                div(
                  classes: 'mt-4 text-center text-sm text-gray-600',
                  [
                    Component.text("Don't have an account? "),
                    a(
                      href: '/register',
                      classes: 'text-blue-600 hover:text-blue-800 font-medium',
                      [Component.text('Register')],
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

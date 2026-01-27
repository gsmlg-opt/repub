import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';

import '../../src/components/layout.dart';
import '../../src/services/auth_api_client.dart';

/// Token management page for viewing and managing API tokens.
@client
class TokensPage extends StatefulComponent {
  const TokensPage({super.key});

  @override
  State<TokensPage> createState() => _TokensPageState();
}

class _TokensPageState extends State<TokensPage> {
  bool _loading = true;
  String? _error;
  List<TokenData> _tokens = [];

  // Create token form
  bool _showCreateForm = false;
  String _newLabel = '';
  int? _expiresInDays;
  Set<String> _selectedScopes = {};
  bool _creating = false;
  String? _createError;
  String? _newToken; // Newly created token (shown once)

  @override
  void initState() {
    super.initState();
    _loadTokens();
  }

  Future<void> _loadTokens() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = AuthApiClient();
    try {
      final tokens = await client.listTokens();
      setState(() {
        _tokens = tokens;
        _loading = false;
      });
    } on AuthApiException catch (e) {
      if (e.statusCode == 401) {
        // Not logged in, redirect to login
        Router.of(context).push('/login');
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load tokens';
        _loading = false;
      });
    } finally {
      client.dispose();
    }
  }

  Future<void> _handleCreateToken() async {
    if (_newLabel.isEmpty) {
      setState(() => _createError = 'Please enter a label for the token');
      return;
    }

    setState(() {
      _creating = true;
      _createError = null;
    });

    final client = AuthApiClient();
    try {
      final token = await client.createToken(
        label: _newLabel,
        scopes: _selectedScopes.toList(),
        expiresInDays: _expiresInDays,
      );
      setState(() {
        _newToken = token;
        _showCreateForm = false;
        _newLabel = '';
        _expiresInDays = null;
        _selectedScopes = {};
        _creating = false;
      });
      await _loadTokens();
    } on AuthApiException catch (e) {
      setState(() {
        _createError = e.message;
        _creating = false;
      });
    } catch (e) {
      setState(() {
        _createError = 'Failed to create token';
        _creating = false;
      });
    } finally {
      client.dispose();
    }
  }

  Future<void> _handleDeleteToken(String label) async {
    final client = AuthApiClient();
    try {
      await client.deleteToken(label);
      await _loadTokens();
    } catch (e) {
      // Ignore errors and reload
      await _loadTokens();
    } finally {
      client.dispose();
    }
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
                div([
                  h1(
                    classes: 'text-3xl font-bold text-gray-900',
                    [Component.text('API Tokens')],
                  ),
                  p(
                    classes: 'text-gray-600 mt-1',
                    [Component.text('Manage tokens for publishing packages')],
                  ),
                ]),
                a(
                  href: '/account',
                  classes: 'text-blue-600 hover:text-blue-800 font-medium',
                  [Component.text('Back to Account')],
                ),
              ],
            ),
            // New token display (shown once after creation)
            if (_newToken != null) _buildNewTokenDisplay(_newToken!),
            // Create token button/form
            if (_showCreateForm)
              _buildCreateForm()
            else
              div(
                classes: 'mb-6',
                [
                  button(
                    type: ButtonType.button,
                    classes:
                        'px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700',
                    events: {
                      'click': (_) => setState(() => _showCreateForm = true)
                    },
                    [Component.text('+ New Token')],
                  ),
                ],
              ),
            // Token list
            if (_loading)
              _buildLoadingState()
            else if (_error != null)
              _buildErrorState(_error!)
            else
              _buildTokenList(),
          ],
        ),
      ],
    );
  }

  Component _buildNewTokenDisplay(String token) {
    return div(
      classes: 'mb-6 p-4 bg-green-50 border border-green-200 rounded-lg',
      [
        div(
          classes: 'flex items-start justify-between',
          [
            div([
              h3(
                classes: 'font-semibold text-green-800',
                [Component.text('Token Created!')],
              ),
              p(
                classes: 'text-sm text-green-700 mt-1',
                [
                  Component.text(
                      'Copy this token now. It will not be shown again.')
                ],
              ),
            ]),
            button(
              type: ButtonType.button,
              classes: 'text-green-600 hover:text-green-800',
              events: {'click': (_) => setState(() => _newToken = null)},
              [Component.text('Dismiss')],
            ),
          ],
        ),
        div(
          classes:
              'mt-3 p-3 bg-white rounded border border-green-300 font-mono text-sm break-all',
          [Component.text(token)],
        ),
        div(
          classes: 'mt-2',
          [
            p(
              classes: 'text-xs text-green-600',
              [
                Component.text(
                    'Use with: dart pub token add <your-registry-url>')
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildCreateForm() {
    return div(
      classes: 'mb-6 bg-white rounded-lg shadow p-6',
      [
        h2(
          classes: 'text-lg font-semibold text-gray-900 mb-4',
          [Component.text('Create New Token')],
        ),
        if (_createError != null)
          div(
            classes:
                'mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm',
            [Component.text(_createError!)],
          ),
        // Label field
        div(
          classes: 'mb-4',
          [
            label(
              classes: 'block text-sm font-medium text-gray-700 mb-1',
              [Component.text('Token Label')],
            ),
            input(
              type: InputType.text,
              classes:
                  'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
              attributes: {
                'value': _newLabel,
                'placeholder': 'e.g., ci-publish, local-dev'
              },
              events: {
                'input': (e) {
                  final target = e.target;
                  if (target != null) {
                    _newLabel = (target as dynamic).value as String;
                  }
                },
              },
            ),
          ],
        ),
        // Expiration select
        div(
          classes: 'mb-4',
          [
            label(
              classes: 'block text-sm font-medium text-gray-700 mb-1',
              [Component.text('Expiration')],
            ),
            select(
              classes:
                  'w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500',
              events: {
                'change': (e) {
                  final target = e.target;
                  if (target != null) {
                    final value = (target as dynamic).value as String;
                    _expiresInDays = value.isEmpty ? null : int.tryParse(value);
                  }
                },
              },
              [
                option(value: '', [Component.text('Never expires')]),
                option(value: '7', [Component.text('7 days')]),
                option(value: '30', [Component.text('30 days')]),
                option(value: '90', [Component.text('90 days')]),
                option(value: '365', [Component.text('1 year')]),
              ],
            ),
          ],
        ),
        // Scopes selection
        div(
          classes: 'mb-4',
          [
            label(
              classes: 'block text-sm font-medium text-gray-700 mb-2',
              [Component.text('Permissions (Scopes)')],
            ),
            p(
              classes: 'text-xs text-gray-500 mb-3',
              [Component.text('Select the permissions this token should have')],
            ),
            // publish:all scope
            div(
              classes: 'flex items-start mb-2',
              [
                input(
                  type: InputType.checkbox,
                  classes: 'mt-1 h-4 w-4 text-blue-600 border-gray-300 rounded',
                  attributes: {
                    'id': 'scope-publish-all',
                    if (_selectedScopes.contains('publish:all'))
                      'checked': 'true',
                  },
                  events: {
                    'change': (e) {
                      final checked = (e.target as dynamic).checked as bool;
                      setState(() {
                        if (checked) {
                          _selectedScopes.add('publish:all');
                        } else {
                          _selectedScopes.remove('publish:all');
                        }
                      });
                    },
                  },
                ),
                label(
                  classes: 'ml-2 flex-1',
                  attributes: {'for': 'scope-publish-all'},
                  [
                    div(
                      classes: 'text-sm font-medium text-gray-700',
                      [Component.text('publish:all')],
                    ),
                    div(
                      classes: 'text-xs text-gray-500',
                      [Component.text('Publish any package to the registry')],
                    ),
                  ],
                ),
              ],
            ),
            // read:all scope
            div(
              classes: 'flex items-start mb-2',
              [
                input(
                  type: InputType.checkbox,
                  classes: 'mt-1 h-4 w-4 text-blue-600 border-gray-300 rounded',
                  attributes: {
                    'id': 'scope-read-all',
                    if (_selectedScopes.contains('read:all')) 'checked': 'true',
                  },
                  events: {
                    'change': (e) {
                      final checked = (e.target as dynamic).checked as bool;
                      setState(() {
                        if (checked) {
                          _selectedScopes.add('read:all');
                        } else {
                          _selectedScopes.remove('read:all');
                        }
                      });
                    },
                  },
                ),
                label(
                  classes: 'ml-2 flex-1',
                  attributes: {'for': 'scope-read-all'},
                  [
                    div(
                      classes: 'text-sm font-medium text-gray-700',
                      [Component.text('read:all')],
                    ),
                    div(
                      classes: 'text-xs text-gray-500',
                      [
                        Component.text(
                            'Download packages (when download auth is required)')
                      ],
                    ),
                  ],
                ),
              ],
            ),
            // Note about package-specific scopes
            div(
              classes: 'mt-2 p-2 bg-blue-50 rounded text-xs text-blue-700',
              [
                Component.text(
                    'Note: For package-specific scopes like publish:pkg:<name>, tokens default to no permissions. Use publish:all for general publishing.')
              ],
            ),
          ],
        ),
        // Buttons
        div(
          classes: 'flex justify-end space-x-3',
          [
            button(
              type: ButtonType.button,
              classes: 'px-4 py-2 text-gray-600 hover:text-gray-900',
              events: {
                'click': (_) => setState(() {
                      _showCreateForm = false;
                      _newLabel = '';
                      _expiresInDays = null;
                      _selectedScopes = {};
                      _createError = null;
                    })
              },
              [Component.text('Cancel')],
            ),
            button(
              type: ButtonType.button,
              classes:
                  'px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50',
              attributes: _creating ? {'disabled': 'true'} : {},
              events: {'click': (_) => _handleCreateToken()},
              [Component.text(_creating ? 'Creating...' : 'Create Token')],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildLoadingState() {
    return div(
      classes: 'bg-white rounded-lg shadow p-6 animate-pulse',
      [
        for (var i = 0; i < 3; i++)
          div(
            classes: 'py-4 border-b last:border-0',
            [
              div(classes: 'h-5 bg-gray-200 rounded w-1/3 mb-2', []),
              div(classes: 'h-4 bg-gray-200 rounded w-1/2', []),
            ],
          ),
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
          events: {'click': (_) => _loadTokens()},
          [Component.text('Try again')],
        ),
      ],
    );
  }

  Component _buildTokenList() {
    if (_tokens.isEmpty) {
      return div(
        classes: 'bg-white rounded-lg shadow p-6 text-center',
        [
          p(
            classes: 'text-gray-500',
            [Component.text('No tokens yet. Create one to get started.')],
          ),
        ],
      );
    }

    return div(
      classes: 'bg-white rounded-lg shadow',
      [
        for (final token in _tokens) _buildTokenCard(token),
      ],
    );
  }

  Component _buildTokenCard(TokenData token) {
    final isExpired = token.isExpired;

    return div(
      classes: 'p-4 border-b last:border-0 ${isExpired ? 'bg-gray-50' : ''}',
      [
        div(
          classes: 'flex items-start justify-between',
          [
            div([
              div(
                classes: 'flex items-center space-x-2',
                [
                  span(
                    classes: 'font-medium text-gray-900',
                    [Component.text(token.label)],
                  ),
                  if (isExpired)
                    span(
                      classes:
                          'px-2 py-0.5 text-xs bg-red-100 text-red-700 rounded',
                      [Component.text('Expired')],
                    ),
                ],
              ),
              div(
                classes: 'text-sm text-gray-500 mt-1',
                [
                  Component.text('Created: ${_formatDate(token.createdAt)}'),
                  if (token.lastUsedAt != null)
                    Component.text(
                        ' | Last used: ${_formatDate(token.lastUsedAt!)}'),
                ],
              ),
              if (token.expiresAt != null)
                div(
                  classes:
                      'text-sm ${isExpired ? 'text-red-500' : 'text-gray-500'} mt-1',
                  [Component.text('Expires: ${_formatDate(token.expiresAt!)}')],
                ),
              // Display scopes
              if (token.scopes.isNotEmpty)
                div(
                  classes: 'flex flex-wrap gap-1 mt-2',
                  [
                    for (final scope in token.scopes)
                      span(
                        classes:
                            'px-2 py-0.5 text-xs bg-blue-100 text-blue-700 rounded font-mono',
                        [Component.text(scope)],
                      ),
                  ],
                )
              else
                div(
                  classes: 'mt-2',
                  [
                    span(
                      classes:
                          'px-2 py-0.5 text-xs bg-gray-100 text-gray-600 rounded',
                      [Component.text('No scopes')],
                    ),
                  ],
                ),
            ]),
            button(
              type: ButtonType.button,
              classes: 'text-red-600 hover:text-red-800 text-sm font-medium',
              events: {'click': (_) => _handleDeleteToken(token.label)},
              [Component.text('Revoke')],
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

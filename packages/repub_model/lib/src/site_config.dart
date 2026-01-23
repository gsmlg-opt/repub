/// Site configuration value types.
enum ConfigValueType {
  string,
  number,
  boolean,
  json,
}

/// A site configuration entry.
class SiteConfig {
  final String name;
  final ConfigValueType valueType;
  final String value;
  final String? description;

  const SiteConfig({
    required this.name,
    required this.valueType,
    required this.value,
    this.description,
  });

  /// Get value as string.
  String get stringValue => value;

  /// Get value as int.
  int get intValue => int.tryParse(value) ?? 0;

  /// Get value as bool.
  bool get boolValue => value.toLowerCase() == 'true';

  /// Convert to JSON for API response.
  Map<String, dynamic> toJson() => {
        'name': name,
        'type': valueType.name,
        'value': value,
        if (description != null) 'description': description,
      };

  /// Create from JSON.
  factory SiteConfig.fromJson(Map<String, dynamic> json) => SiteConfig(
        name: json['name'] as String,
        valueType: ConfigValueType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ConfigValueType.string,
        ),
        value: json['value'] as String,
        description: json['description'] as String?,
      );
}

/// Default site configuration values.
class SiteConfigDefaults {
  static const allowRegistration = SiteConfig(
    name: 'allow_registration',
    valueType: ConfigValueType.boolean,
    value: 'true',
    description: 'Allow new user registration',
  );

  static const requireEmailVerification = SiteConfig(
    name: 'require_email_verification',
    valueType: ConfigValueType.boolean,
    value: 'false',
    description: 'Require email verification for new users',
  );

  static const allowAnonymousPublish = SiteConfig(
    name: 'allow_anonymous_publish',
    valueType: ConfigValueType.boolean,
    value: 'true',
    description: 'Allow publishing packages without authentication',
  );

  static const sessionTtlHours = SiteConfig(
    name: 'session_ttl_hours',
    valueType: ConfigValueType.number,
    value: '24',
    description: 'Web session duration in hours',
  );

  static const tokenMaxTtlDays = SiteConfig(
    name: 'token_max_ttl_days',
    valueType: ConfigValueType.number,
    value: '0',
    description: 'Maximum token lifetime in days (0 = unlimited)',
  );

  static const oauthGithubClientId = SiteConfig(
    name: 'oauth_github_client_id',
    valueType: ConfigValueType.string,
    value: '',
    description: 'GitHub OAuth client ID',
  );

  static const oauthGithubClientSecret = SiteConfig(
    name: 'oauth_github_client_secret',
    valueType: ConfigValueType.string,
    value: '',
    description: 'GitHub OAuth client secret',
  );

  static const oauthGoogleClientId = SiteConfig(
    name: 'oauth_google_client_id',
    valueType: ConfigValueType.string,
    value: '',
    description: 'Google OAuth client ID',
  );

  static const oauthGoogleClientSecret = SiteConfig(
    name: 'oauth_google_client_secret',
    valueType: ConfigValueType.string,
    value: '',
    description: 'Google OAuth client secret',
  );

  /// All default configurations.
  static const all = [
    allowRegistration,
    requireEmailVerification,
    allowAnonymousPublish,
    sessionTtlHours,
    tokenMaxTtlDays,
    oauthGithubClientId,
    oauthGithubClientSecret,
    oauthGoogleClientId,
    oauthGoogleClientSecret,
  ];
}

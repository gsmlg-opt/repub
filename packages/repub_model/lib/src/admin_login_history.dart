/// A login history entry for an admin user.
class AdminLoginHistory {
  final String id;
  final String adminUserId;
  final DateTime loginAt;
  final String? ipAddress;
  final String? userAgent;
  final bool success;

  const AdminLoginHistory({
    required this.id,
    required this.adminUserId,
    required this.loginAt,
    this.ipAddress,
    this.userAgent,
    required this.success,
  });

  /// Convert to JSON for API response.
  Map<String, dynamic> toJson() => {
        'id': id,
        'adminUserId': adminUserId,
        'loginAt': loginAt.toUtc().toIso8601String(),
        if (ipAddress != null) 'ipAddress': ipAddress,
        if (userAgent != null) 'userAgent': userAgent,
        'success': success,
      };

  /// Create from JSON.
  factory AdminLoginHistory.fromJson(Map<String, dynamic> json) =>
      AdminLoginHistory(
        id: json['id'] as String,
        adminUserId: json['adminUserId'] as String,
        loginAt: DateTime.parse(json['loginAt'] as String),
        ipAddress: json['ipAddress'] as String?,
        userAgent: json['userAgent'] as String?,
        success: json['success'] as bool,
      );
}

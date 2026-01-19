/// Represents an in-progress upload session.
class UploadSession {
  final String id;
  final DateTime createdAt;
  final DateTime expiresAt;

  const UploadSession({
    required this.id,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class UserModel {
  final int id;
  final int telegramId;
  final String? username;
  final String fullName;
  final double balance;
  final String createdAt;

  const UserModel({
    required this.id,
    required this.telegramId,
    required this.username,
    required this.fullName,
    required this.balance,
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, Object?> map) {
    return UserModel(
      id: map['id'] as int,
      telegramId: map['telegram_id'] as int,
      username: map['username'] as String?,
      fullName: map['full_name'] as String? ?? '',
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      createdAt: map['created_at'] as String? ?? '',
    );
  }
}

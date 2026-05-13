class AccountModel {
  final int id;
  final int categoryId;
  final String username;
  final String password;
  final String? extraInfo;
  final int isSold;
  final int? soldTo;
  final String? soldAt;
  final String createdAt;

  const AccountModel({
    required this.id,
    required this.categoryId,
    required this.username,
    required this.password,
    this.extraInfo,
    required this.isSold,
    this.soldTo,
    this.soldAt,
    required this.createdAt,
  });

  factory AccountModel.fromMap(Map<String, Object?> map) {
    return AccountModel(
      id: map['id'] as int,
      categoryId: map['category_id'] as int,
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      extraInfo: map['extra_info'] as String?,
      isSold: map['is_sold'] as int? ?? 0,
      soldTo: map['sold_to'] as int?,
      soldAt: map['sold_at'] as String?,
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'username': username,
      'password': password,
      'extra_info': extraInfo,
      'is_sold': isSold,
      'sold_to': soldTo,
      'sold_at': soldAt,
      'created_at': createdAt,
    };
  }
}

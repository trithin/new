import 'package:telegram_account_shop_bot/database/database.dart';

String buildHistoryMessage({required AppDatabase db, required int telegramId}) {
  final history = db.getRecentPurchases(telegramId, limit: 10);
  if (history.isEmpty) {
    return '📋 Bạn chưa có giao dịch mua nào.';
  }

  final buffer = StringBuffer('📋 10 giao dịch mua gần nhất:\n\n');
  for (final row in history) {
    buffer.writeln(
      '- ${row['created_at']} | ${row['category_name'] ?? 'Không rõ'} | ${((row['amount'] as num?) ?? 0).toStringAsFixed(0)} VNĐ',
    );
  }

  return buffer.toString();
}

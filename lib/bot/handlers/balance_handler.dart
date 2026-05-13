import 'package:telegram_account_shop_bot/database/database.dart';

String buildBalanceMessage({required AppDatabase db, required int telegramId}) {
  final user = db.getUserByTelegramId(telegramId);
  if (user == null) {
    return 'Bạn chưa đăng ký. Hãy gõ /start trước.';
  }

  return '💰 Số dư hiện tại: ${user.balance.toStringAsFixed(0)} VNĐ';
}

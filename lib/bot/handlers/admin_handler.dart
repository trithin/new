import 'package:telegram_account_shop_bot/config.dart';
import 'package:telegram_account_shop_bot/database/database.dart';

bool isAdmin(int telegramId) => telegramId == Config.adminId && Config.adminId != 0;

String handleAddBalanceCommand({
  required AppDatabase db,
  required int fromTelegramId,
  required List<String> args,
}) {
  if (!isAdmin(fromTelegramId)) {
    return 'Bạn không có quyền dùng lệnh này.';
  }

  if (args.length != 2) {
    return 'Cú pháp: /addbalance [user_id] [amount]';
  }

  final userId = int.tryParse(args[0]);
  final amount = double.tryParse(args[1]);
  if (userId == null || amount == null || amount <= 0) {
    return 'Dữ liệu không hợp lệ.';
  }

  final user = db.getUserByTelegramId(userId);
  if (user == null) {
    return 'Không tìm thấy user telegram_id=$userId';
  }

  db.addBalanceByUserId(userId: user.id, amount: amount);
  return 'Đã cộng ${amount.toStringAsFixed(0)} VNĐ cho user $userId.';
}

String handleStatsCommand({
  required AppDatabase db,
  required int fromTelegramId,
}) {
  if (!isAdmin(fromTelegramId)) {
    return 'Bạn không có quyền dùng lệnh này.';
  }

  final stats = db.getStats();
  return '''📊 Thống kê hệ thống

Tổng user: ${stats['total_users']}
Doanh thu: ${((stats['total_revenue'] as num?) ?? 0).toStringAsFixed(0)} VNĐ
Tài khoản đã bán: ${stats['sold_accounts']}
Tài khoản còn lại: ${stats['remaining_accounts']}''';
}

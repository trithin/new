import 'dart:async';

import 'package:telegram_account_shop_bot/bot/bot.dart';
import 'package:telegram_account_shop_bot/config.dart';
import 'package:telegram_account_shop_bot/database/database.dart';
import 'package:telegram_account_shop_bot/server/server.dart';

Future<void> main() async {
  final db = AppDatabase();
  db.init();

  if (Config.adminId == 0) {
    print('Cảnh báo: ADMIN_ID đang là 0, lệnh admin bot sẽ không hoạt động.');
  }
  if (Config.jwtSecret == 'secret_key_change_me') {
    print('Cảnh báo bảo mật: JWT_SECRET đang dùng giá trị mặc định.');
  }

  await Future.wait([
    runBot(db),
    runServer(db),
  ]);
}

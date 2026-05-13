import 'dart:async';

import 'package:telegram_account_shop_bot/bot/bot.dart';
import 'package:telegram_account_shop_bot/database/database.dart';
import 'package:telegram_account_shop_bot/server/server.dart';

Future<void> main() async {
  final db = AppDatabase();
  db.init();

  await Future.wait([
    runBot(db),
    runServer(db),
  ]);
}

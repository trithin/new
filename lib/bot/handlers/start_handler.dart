import 'package:telegram_account_shop_bot/bot/keyboards.dart';
import 'package:telegram_account_shop_bot/database/database.dart';
import 'package:teledart/model.dart';
import 'package:teledart/teledart.dart';

Future<void> handleStart({
  required TeleDart bot,
  required AppDatabase db,
  required Message message,
}) async {
  final from = message.from;
  if (from == null) {
    return;
  }

  db.createOrGetUser(
    telegramId: from.id,
    username: from.username,
    fullName: [from.firstName, from.lastName].whereType<String>().join(' ').trim(),
  );

  await bot.telegram.sendMessage(
    message.chat.id,
    'Chào mừng ${from.firstName ?? 'bạn'} đến với bot bán tài khoản!\n\nChọn chức năng bên dưới:',
    replyMarkup: mainMenuKeyboard(),
  );
}

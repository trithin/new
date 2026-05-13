import 'dart:async';

import 'package:telegram_account_shop_bot/bot/handlers/admin_handler.dart';
import 'package:telegram_account_shop_bot/bot/handlers/balance_handler.dart';
import 'package:telegram_account_shop_bot/bot/handlers/deposit_handler.dart';
import 'package:telegram_account_shop_bot/bot/handlers/shop_handler.dart';
import 'package:telegram_account_shop_bot/bot/handlers/start_handler.dart';
import 'package:telegram_account_shop_bot/bot/keyboards.dart';
import 'package:telegram_account_shop_bot/config.dart';
import 'package:telegram_account_shop_bot/database/database.dart';
import 'package:teledart/model.dart';
import 'package:teledart/teledart.dart';
import 'package:teledart/telegram.dart';

Future<void> runBot(AppDatabase db) async {
  if (Config.botToken == 'YOUR_BOT_TOKEN') {
    print('BOT_TOKEN chưa được cấu hình, bot sẽ không khởi động.');
    return;
  }

  final telegram = Telegram(Config.botToken);
  final me = await telegram.getMe();
  final username = me.username;
  if (username == null || username.isEmpty) {
    throw StateError('Bot username không hợp lệ');
  }

  final bot = TeleDart(Config.botToken, Event(username));
  bot.start();

  bot.onCommand('start').listen((message) async {
    await handleStart(bot: bot, db: db, message: message);
  });

  bot.onCommand('addbalance').listen((message) async {
    final text = message.text ?? '';
    final parts = text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final args = parts.length > 1 ? parts.sublist(1) : const <String>[];
    final response = handleAddBalanceCommand(
      db: db,
      fromTelegramId: message.from?.id ?? 0,
      args: args,
    );
    await bot.sendMessage(message.chat.id, response);
  });

  bot.onCommand('stats').listen((message) async {
    final response = handleStatsCommand(
      db: db,
      fromTelegramId: message.from?.id ?? 0,
    );
    await bot.sendMessage(message.chat.id, response);
  });

  bot.onCallbackQuery().listen((query) async {
    try {
      await _handleCallback(bot: bot, db: db, query: query);
    } catch (e) {
      await bot.answerCallbackQuery(
        query.id,
        text: 'Có lỗi xảy ra: $e',
        showAlert: true,
      );
    }
  });

  print('Telegram bot đã chạy @${me.username}');
  await Completer<void>().future;
}

Future<void> _handleCallback({
  required TeleDart bot,
  required AppDatabase db,
  required CallbackQuery query,
}) async {
  final data = query.data ?? '';
  final from = query.from;
  final message = query.message;
  if (message == null) {
    return;
  }

  db.createOrGetUser(
    telegramId: from.id,
    username: from.username,
    fullName: [from.firstName, from.lastName].whereType<String>().join(' ').trim(),
  );

  if (data == 'balance') {
    await bot.sendMessage(
      message.chat.id,
      buildBalanceMessage(db: db, telegramId: from.id),
      replyMarkup: mainMenuKeyboard(),
    );
    await bot.answerCallbackQuery(query.id);
    return;
  }

  if (data == 'deposit') {
    await bot.sendMessage(
      message.chat.id,
      buildDepositMessage(from.id),
      replyMarkup: mainMenuKeyboard(),
    );
    await bot.answerCallbackQuery(query.id);
    return;
  }

  if (data == 'history') {
    await bot.sendMessage(
      message.chat.id,
      buildHistoryMessage(db: db, telegramId: from.id),
      replyMarkup: mainMenuKeyboard(),
    );
    await bot.answerCallbackQuery(query.id);
    return;
  }

  if (data == 'shop') {
    final categories = db.getActiveCategoriesWithStock();
    await bot.sendMessage(
      message.chat.id,
      categories.isEmpty
          ? 'Hiện chưa có danh mục đang hoạt động.'
          : '🛒 Chọn danh mục muốn mua:',
      replyMarkup: categories.isEmpty ? mainMenuKeyboard() : categoriesKeyboard(categories),
    );
    await bot.answerCallbackQuery(query.id);
    return;
  }

  if (data == 'back_menu') {
    await bot.sendMessage(
      message.chat.id,
      'Menu chính:',
      replyMarkup: mainMenuKeyboard(),
    );
    await bot.answerCallbackQuery(query.id);
    return;
  }

  if (data.startsWith('category_')) {
    final categoryId = int.tryParse(data.replaceFirst('category_', ''));
    if (categoryId == null) {
      await bot.answerCallbackQuery(query.id, text: 'Danh mục không hợp lệ');
      return;
    }

    final category = db.getCategoryWithStock(categoryId);
    if (category == null) {
      await bot.answerCallbackQuery(query.id, text: 'Danh mục không tồn tại');
      return;
    }

    await bot.sendMessage(
      message.chat.id,
      '${category.emoji} ${category.name}\n'
      'Giá: ${category.price.toStringAsFixed(0)} VNĐ\n'
      'Còn: ${category.stock}',
      replyMarkup: buyKeyboard(category.id),
    );
    await bot.answerCallbackQuery(query.id);
    return;
  }

  if (data.startsWith('buy_')) {
    final categoryId = int.tryParse(data.replaceFirst('buy_', ''));
    if (categoryId == null) {
      await bot.answerCallbackQuery(query.id, text: 'Dữ liệu không hợp lệ');
      return;
    }

    await bot.sendMessage(
      message.chat.id,
      'Bạn có chắc muốn mua tài khoản này?',
      replyMarkup: confirmBuyKeyboard(categoryId),
    );
    await bot.answerCallbackQuery(query.id);
    return;
  }

  if (data.startsWith('confirm_buy_')) {
    final categoryId = int.tryParse(data.replaceFirst('confirm_buy_', ''));
    if (categoryId == null) {
      await bot.answerCallbackQuery(query.id, text: 'Dữ liệu không hợp lệ');
      return;
    }

    final result = db.buyAccount(telegramId: from.id, categoryId: categoryId);
    if (!result.ok) {
      await bot.sendMessage(
        message.chat.id,
        result.message,
        replyMarkup: mainMenuKeyboard(),
      );
      await bot.answerCallbackQuery(query.id, text: result.message, showAlert: true);
      return;
    }

    final account = result.account!;
    final category = result.category!;
    await bot.sendMessage(
      message.chat.id,
      '✅ Mua thành công ${category.name}\n\n'
      'Username: ${account.username}\n'
      'Password: ${account.password}\n'
      '${account.extraInfo == null ? '' : 'Extra: ${account.extraInfo}\n'}',
      replyMarkup: mainMenuKeyboard(),
    );
    await bot.answerCallbackQuery(query.id, text: 'Mua thành công');
    return;
  }

  await bot.answerCallbackQuery(query.id, text: 'Hành động không hỗ trợ');
}

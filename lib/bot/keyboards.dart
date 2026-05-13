import 'package:telegram_account_shop_bot/models/category.dart';
import 'package:teledart/model.dart';

InlineKeyboardMarkup mainMenuKeyboard() {
  return InlineKeyboardMarkup(inlineKeyboard: [
    [InlineKeyboardButton(text: '💰 Số dư', callbackData: 'balance')],
    [InlineKeyboardButton(text: '🛒 Mua tài khoản', callbackData: 'shop')],
    [InlineKeyboardButton(text: '💳 Nạp tiền', callbackData: 'deposit')],
    [InlineKeyboardButton(text: '📋 Lịch sử mua', callbackData: 'history')],
  ]);
}

InlineKeyboardMarkup categoriesKeyboard(List<CategoryModel> categories) {
  final rows = <List<InlineKeyboardButton>>[];
  for (final category in categories) {
    rows.add([
      InlineKeyboardButton(
        text: '${category.emoji} ${category.name} (còn: ${category.stock})',
        callbackData: 'category_${category.id}',
      ),
    ]);
  }
  rows.add([
    InlineKeyboardButton(text: '⬅️ Quay lại', callbackData: 'back_menu'),
  ]);

  return InlineKeyboardMarkup(inlineKeyboard: rows);
}

InlineKeyboardMarkup buyKeyboard(int categoryId) {
  return InlineKeyboardMarkup(inlineKeyboard: [
    [InlineKeyboardButton(text: '🛒 Mua ngay', callbackData: 'buy_$categoryId')],
    [InlineKeyboardButton(text: '⬅️ Danh mục', callbackData: 'shop')],
  ]);
}

InlineKeyboardMarkup confirmBuyKeyboard(int categoryId) {
  return InlineKeyboardMarkup(inlineKeyboard: [
    [InlineKeyboardButton(text: '✅ Xác nhận mua', callbackData: 'confirm_buy_$categoryId')],
    [InlineKeyboardButton(text: '❌ Hủy', callbackData: 'shop')],
  ]);
}

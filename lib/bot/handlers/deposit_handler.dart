import 'package:telegram_account_shop_bot/config.dart';

String buildDepositMessage(int telegramId) {
  return '''💳 Hướng dẫn nạp tiền

Ngân hàng: ${Config.bankName}
Số tài khoản: ${Config.bankAccount}
Chủ tài khoản: ${Config.bankOwner}

Nội dung chuyển khoản: NAP_$telegramId

Sau khi chuyển khoản, admin sẽ xác nhận và cộng số dư cho bạn.''';
}

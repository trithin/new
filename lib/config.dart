import 'dart:io';

class Config {
  static String get botToken =>
      Platform.environment['BOT_TOKEN'] ?? 'YOUR_BOT_TOKEN';

  static int get adminId =>
      int.tryParse(Platform.environment['ADMIN_ID'] ?? '0') ?? 0;

  static String get adminUsername =>
      Platform.environment['ADMIN_USERNAME'] ?? 'admin';

  static String get adminPassword =>
      Platform.environment['ADMIN_PASSWORD'] ?? 'admin123';

  static String get jwtSecret =>
      Platform.environment['JWT_SECRET'] ?? 'secret_key_change_me';

  static const int serverPort = 8080;

  static const String bankName = 'Vietcombank';
  static const String bankAccount = '1234567890';
  static const String bankOwner = 'NGUYEN VAN A';
}

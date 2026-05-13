class Config {
  static const String botToken = String.fromEnvironment(
    'BOT_TOKEN',
    defaultValue: 'YOUR_BOT_TOKEN',
  );
  static const int adminId = int.fromEnvironment('ADMIN_ID', defaultValue: 0);
  static const String adminUsername = String.fromEnvironment(
    'ADMIN_USERNAME',
    defaultValue: 'admin',
  );
  static const String adminPassword = String.fromEnvironment(
    'ADMIN_PASSWORD',
    defaultValue: 'admin123',
  );
  static const String jwtSecret = String.fromEnvironment(
    'JWT_SECRET',
    defaultValue: 'secret_key_change_me',
  );
  static const int serverPort = 8080;

  static const String bankName = 'Vietcombank';
  static const String bankAccount = '1234567890';
  static const String bankOwner = 'NGUYEN VAN A';
}

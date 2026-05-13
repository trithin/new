import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:telegram_account_shop_bot/models/account.dart';
import 'package:telegram_account_shop_bot/models/category.dart';
import 'package:telegram_account_shop_bot/models/user.dart';

class PurchaseResult {
  final bool ok;
  final String message;
  final AccountModel? account;
  final CategoryModel? category;

  const PurchaseResult({
    required this.ok,
    required this.message,
    this.account,
    this.category,
  });
}

class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;

  late final Database _db;

  void init() {
    _db = sqlite3.open('app.db');
    _db.execute('PRAGMA foreign_keys = ON;');
    _createTables();
    _seedCategoriesIfEmpty();
  }

  void _createTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        telegram_id INTEGER UNIQUE NOT NULL,
        username TEXT,
        full_name TEXT,
        balance REAL DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        price REAL NOT NULL,
        emoji TEXT DEFAULT '🔑',
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        extra_info TEXT,
        is_sold INTEGER DEFAULT 0,
        sold_to INTEGER,
        sold_at TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (category_id) REFERENCES categories(id)
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        account_id INTEGER,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
    ''');
  }

  int _changes() {
    final row = _db.select('SELECT changes() AS count').first;
    return row['count'] as int;
  }

  List<Map<String, Object?>> _rows(ResultSet resultSet) {
    return resultSet.map((row) => Map<String, Object?>.from(row)).toList();
  }

  void _seedCategoriesIfEmpty() {
    final count = _db.select('SELECT COUNT(*) AS count FROM categories').first['count'] as int;
    if (count > 0) {
      return;
    }

    _db.execute(
      '''
      INSERT INTO categories(name, description, price, emoji, is_active)
      VALUES
      ('Tài khoản thường', 'Tài khoản cơ bản', 10000, '🟢', 1),
      ('Tài khoản Pro', 'Tài khoản cao cấp', 50000, '⭐', 1),
      ('Tài khoản Web A', 'Tài khoản dịch vụ web A', 30000, '🌐', 1),
      ('Tài khoản Web B', 'Tài khoản dịch vụ web B', 35000, '🌐', 1)
      ''',
    );
  }

  UserModel createOrGetUser({
    required int telegramId,
    String? username,
    required String fullName,
  }) {
    _db.execute(
      '''
      INSERT INTO users(telegram_id, username, full_name)
      VALUES (?, ?, ?)
      ON CONFLICT(telegram_id) DO UPDATE SET
        username = excluded.username,
        full_name = excluded.full_name
      ''',
      [telegramId, username, fullName],
    );

    return getUserByTelegramId(telegramId)!;
  }

  UserModel? getUserByTelegramId(int telegramId) {
    final rows = _db.select(
      'SELECT * FROM users WHERE telegram_id = ? LIMIT 1',
      [telegramId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return UserModel.fromMap(rows.first);
  }

  UserModel? getUserById(int userId) {
    final rows = _db.select('SELECT * FROM users WHERE id = ? LIMIT 1', [userId]);
    if (rows.isEmpty) {
      return null;
    }
    return UserModel.fromMap(rows.first);
  }

  List<Map<String, Object?>> getRecentPurchases(int telegramId, {int limit = 10}) {
    return _rows(_db.select(
      '''
      SELECT t.created_at, t.amount, c.name AS category_name
      FROM transactions t
      LEFT JOIN accounts a ON a.id = t.account_id
      LEFT JOIN categories c ON c.id = a.category_id
      INNER JOIN users u ON u.id = t.user_id
      WHERE u.telegram_id = ? AND t.type = 'purchase'
      ORDER BY t.id DESC
      LIMIT ?
      ''',
      [telegramId, limit],
    ));
  }

  List<CategoryModel> getActiveCategoriesWithStock() {
    final rows = _db.select('''
      SELECT c.*, COALESCE(COUNT(a.id), 0) AS stock
      FROM categories c
      LEFT JOIN accounts a ON a.category_id = c.id AND a.is_sold = 0
      WHERE c.is_active = 1
      GROUP BY c.id
      ORDER BY c.id ASC
    ''');
    return rows.map((row) => CategoryModel.fromMap(row)).toList();
  }

  CategoryModel? getCategoryWithStock(int categoryId) {
    final rows = _db.select(
      '''
      SELECT c.*, COALESCE(COUNT(a.id), 0) AS stock
      FROM categories c
      LEFT JOIN accounts a ON a.category_id = c.id AND a.is_sold = 0
      WHERE c.id = ? AND c.is_active = 1
      GROUP BY c.id
      LIMIT 1
      ''',
      [categoryId],
    );

    if (rows.isEmpty) {
      return null;
    }

    return CategoryModel.fromMap(rows.first);
  }

  PurchaseResult buyAccount({
    required int telegramId,
    required int categoryId,
  }) {
    final user = getUserByTelegramId(telegramId);
    if (user == null) {
      return const PurchaseResult(ok: false, message: 'Không tìm thấy người dùng. Hãy dùng /start trước.');
    }

    final category = getCategoryWithStock(categoryId);
    if (category == null) {
      return const PurchaseResult(ok: false, message: 'Danh mục không tồn tại hoặc đang tắt.');
    }

    if (category.stock <= 0) {
      return const PurchaseResult(ok: false, message: 'Danh mục đã hết hàng.');
    }

    if (user.balance < category.price) {
      return const PurchaseResult(ok: false, message: 'Số dư không đủ. Vui lòng nạp thêm tiền.');
    }

    _db.execute('BEGIN');
    try {
      final selected = _db.select(
        'SELECT * FROM accounts WHERE category_id = ? AND is_sold = 0 ORDER BY id ASC LIMIT 1',
        [categoryId],
      );

      if (selected.isEmpty) {
        _db.execute('ROLLBACK');
        return const PurchaseResult(ok: false, message: 'Danh mục vừa hết hàng.');
      }

      final account = AccountModel.fromMap(selected.first);

      _db.execute(
        'UPDATE users SET balance = balance - ? WHERE id = ?',
        [category.price, user.id],
      );

      _db.execute(
        '''
        UPDATE accounts
        SET is_sold = 1,
            sold_to = ?,
            sold_at = CURRENT_TIMESTAMP
        WHERE id = ?
        ''',
        [user.id, account.id],
      );

      _db.execute(
        '''
        INSERT INTO transactions(user_id, type, amount, description, account_id)
        VALUES (?, 'purchase', ?, ?, ?)
        ''',
        [user.id, category.price, 'Mua ${category.name}', account.id],
      );

      _db.execute('COMMIT');
      return PurchaseResult(
        ok: true,
        message: 'Mua tài khoản thành công.',
        account: account,
        category: category,
      );
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  bool addBalanceByTelegramId({required int telegramId, required double amount}) {
    final user = getUserByTelegramId(telegramId);
    if (user == null) {
      return false;
    }
    addBalanceByUserId(userId: user.id, amount: amount);
    return true;
  }

  void addBalanceByUserId({required int userId, required double amount}) {
    _db.execute('BEGIN');
    try {
      _db.execute(
        'UPDATE users SET balance = balance + ? WHERE id = ?',
        [amount, userId],
      );
      _db.execute(
        '''
        INSERT INTO transactions(user_id, type, amount, description)
        VALUES (?, 'deposit', ?, ?)
        ''',
        [userId, amount, 'Admin cộng số dư'],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, Object?> getStats() {
    final users = _db.select('SELECT COUNT(*) AS total FROM users').first['total'] as int;
    final soldAccounts = _db.select(
      'SELECT COUNT(*) AS total FROM accounts WHERE is_sold = 1',
    ).first['total'] as int;
    final remainAccounts = _db.select(
      'SELECT COUNT(*) AS total FROM accounts WHERE is_sold = 0',
    ).first['total'] as int;
    final revenue = (_db.select(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE type = 'purchase'",
    ).first['total'] as num)
        .toDouble();

    final recentTransactions = _rows(_db.select('''
      SELECT t.id, t.type, t.amount, t.description, t.created_at, u.telegram_id, u.full_name
      FROM transactions t
      LEFT JOIN users u ON u.id = t.user_id
      ORDER BY t.id DESC
      LIMIT 10
    '''));

    return {
      'total_users': users,
      'sold_accounts': soldAccounts,
      'remaining_accounts': remainAccounts,
      'total_revenue': revenue,
      'recent_transactions': recentTransactions,
    };
  }

  List<Map<String, Object?>> listUsers() {
    return _rows(_db.select('SELECT * FROM users ORDER BY id DESC'));
  }

  List<Map<String, Object?>> listCategories() {
    final rows = _db.select('''
      SELECT c.*, COALESCE(COUNT(a.id), 0) AS stock
      FROM categories c
      LEFT JOIN accounts a ON a.category_id = c.id AND a.is_sold = 0
      GROUP BY c.id
      ORDER BY c.id DESC
    ''');
    return _rows(rows);
  }

  int createCategory({
    required String name,
    String? description,
    required double price,
    required String emoji,
  }) {
    _db.execute(
      'INSERT INTO categories(name, description, price, emoji) VALUES (?, ?, ?, ?)',
      [name, description, price, emoji],
    );
    final row = _db.select('SELECT last_insert_rowid() AS id').first;
    return row['id'] as int;
  }

  bool updateCategory({
    required int id,
    required String name,
    String? description,
    required double price,
    required String emoji,
    required int isActive,
  }) {
    _db.execute(
      '''
      UPDATE categories
      SET name = ?, description = ?, price = ?, emoji = ?, is_active = ?
      WHERE id = ?
      ''',
      [name, description, price, emoji, isActive, id],
    );
    return _changes() > 0;
  }

  bool deleteCategory(int id) {
    final sold = _db.select(
      'SELECT COUNT(*) AS total FROM accounts WHERE category_id = ? AND is_sold = 1',
      [id],
    ).first['total'] as int;
    if (sold > 0) {
      return false;
    }

    _db.execute('DELETE FROM accounts WHERE category_id = ?', [id]);
    _db.execute('DELETE FROM categories WHERE id = ?', [id]);
    return _changes() > 0;
  }

  List<Map<String, Object?>> listAccounts({int? categoryId, int? sold}) {
    final where = <String>[];
    final params = <Object?>[];

    if (categoryId != null) {
      where.add('a.category_id = ?');
      params.add(categoryId);
    }
    if (sold != null) {
      where.add('a.is_sold = ?');
      params.add(sold);
    }

    final condition = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    return _rows(_db.select(
      '''
      SELECT a.*, c.name AS category_name, c.emoji AS category_emoji
      FROM accounts a
      LEFT JOIN categories c ON c.id = a.category_id
      $condition
      ORDER BY a.id DESC
      ''',
      params,
    ));
  }

  int createAccount({
    required int categoryId,
    required String username,
    required String password,
    String? extraInfo,
  }) {
    _db.execute(
      '''
      INSERT INTO accounts(category_id, username, password, extra_info)
      VALUES (?, ?, ?, ?)
      ''',
      [categoryId, username, password, extraInfo],
    );

    final row = _db.select('SELECT last_insert_rowid() AS id').first;
    return row['id'] as int;
  }

  int bulkCreateAccounts({required int categoryId, required List<String> lines}) {
    var inserted = 0;
    _db.execute('BEGIN');
    try {
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) {
          continue;
        }

        final parts = line.split(':');
        if (parts.length < 2) {
          continue;
        }

        final username = parts[0].trim();
        final password = parts[1].trim();
        final extraInfo = parts.length > 2 ? parts.sublist(2).join(':').trim() : null;

        if (username.isEmpty || password.isEmpty) {
          continue;
        }

        _db.execute(
          '''
          INSERT INTO accounts(category_id, username, password, extra_info)
          VALUES (?, ?, ?, ?)
          ''',
          [categoryId, username, password, extraInfo?.isEmpty == true ? null : extraInfo],
        );
        inserted++;
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }

    return inserted;
  }

  bool deleteAccount(int id) {
    _db.execute('DELETE FROM accounts WHERE id = ? AND is_sold = 0', [id]);
    return _changes() > 0;
  }

  String exportAsJson() {
    final data = {
      'users': listUsers(),
      'categories': listCategories(),
      'accounts': listAccounts(),
      'stats': getStats(),
    };

    return jsonEncode(data);
  }
}

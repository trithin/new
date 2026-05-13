import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:telegram_account_shop_bot/database/database.dart';

Router accountRoutes(AppDatabase db) {
  final router = Router();

  router.get('/', (Request request) {
    final categoryId = int.tryParse(request.url.queryParameters['category_id'] ?? '');
    final sold = int.tryParse(request.url.queryParameters['sold'] ?? '');

    final accounts = db.listAccounts(categoryId: categoryId, sold: sold);
    return Response.ok(
      jsonEncode(accounts),
      headers: {'content-type': 'application/json'},
    );
  });

  router.post('/', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final categoryId = (body['category_id'] as num?)?.toInt();
    final username = body['username']?.toString().trim() ?? '';
    final password = body['password']?.toString().trim() ?? '';
    final extraInfo = body['extra_info']?.toString();

    if (categoryId == null || username.isEmpty || password.isEmpty) {
      return Response(400,
          body: jsonEncode({'message': 'Dữ liệu không hợp lệ'}),
          headers: {'content-type': 'application/json'});
    }

    final id = db.createAccount(
      categoryId: categoryId,
      username: username,
      password: password,
      extraInfo: extraInfo,
    );

    return Response.ok(
      jsonEncode({'id': id}),
      headers: {'content-type': 'application/json'},
    );
  });

  router.post('/bulk', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final categoryId = (body['category_id'] as num?)?.toInt();
    final lines = (body['lines'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

    if (categoryId == null || lines.isEmpty) {
      return Response(400,
          body: jsonEncode({'message': 'Dữ liệu không hợp lệ'}),
          headers: {'content-type': 'application/json'});
    }

    final inserted = db.bulkCreateAccounts(categoryId: categoryId, lines: lines);
    return Response.ok(
      jsonEncode({'inserted': inserted}),
      headers: {'content-type': 'application/json'},
    );
  });

  router.delete('/<id>', (Request request, String id) {
    final accountId = int.tryParse(id);
    if (accountId == null) {
      return Response(400,
          body: jsonEncode({'message': 'ID không hợp lệ'}),
          headers: {'content-type': 'application/json'});
    }

    final ok = db.deleteAccount(accountId);
    if (!ok) {
      return Response(400,
          body: jsonEncode({'message': 'Chỉ được xóa tài khoản chưa bán'}),
          headers: {'content-type': 'application/json'});
    }

    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}

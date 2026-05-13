import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:telegram_account_shop_bot/database/database.dart';

Router userRoutes(AppDatabase db) {
  final router = Router();

  router.get('/', (Request request) {
    final users = db.listUsers();
    return Response.ok(
      jsonEncode(users),
      headers: {'content-type': 'application/json'},
    );
  });

  router.post('/<id>/add-balance', (Request request, String id) async {
    final userId = int.tryParse(id);
    if (userId == null) {
      return Response(400,
          body: jsonEncode({'message': 'ID không hợp lệ'}),
          headers: {'content-type': 'application/json'});
    }

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final amount = double.tryParse(body['amount'].toString());

    if (amount == null || amount <= 0) {
      return Response(400,
          body: jsonEncode({'message': 'Số tiền không hợp lệ'}),
          headers: {'content-type': 'application/json'});
    }

    final user = db.getUserById(userId);
    if (user == null) {
      return Response.notFound(
        jsonEncode({'message': 'Không tìm thấy user'}),
        headers: {'content-type': 'application/json'},
      );
    }

    db.addBalanceByUserId(userId: userId, amount: amount);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}

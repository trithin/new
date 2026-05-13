import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:telegram_account_shop_bot/database/database.dart';

Router categoryRoutes(AppDatabase db) {
  final router = Router();

  router.get('/', (Request request) {
    return Response.ok(
      jsonEncode(db.listCategories()),
      headers: {'content-type': 'application/json'},
    );
  });

  router.post('/', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final name = body['name']?.toString().trim() ?? '';
    final description = body['description']?.toString();
    final price = double.tryParse(body['price'].toString());
    final emoji = (body['emoji']?.toString().trim().isNotEmpty ?? false)
        ? body['emoji'].toString().trim()
        : '🔑';

    if (name.isEmpty || price == null || price <= 0) {
      return Response(400,
          body: jsonEncode({'message': 'Dữ liệu không hợp lệ'}),
          headers: {'content-type': 'application/json'});
    }

    final id = db.createCategory(
      name: name,
      description: description,
      price: price,
      emoji: emoji,
    );

    return Response.ok(
      jsonEncode({'id': id}),
      headers: {'content-type': 'application/json'},
    );
  });

  router.put('/<id>', (Request request, String id) async {
    final categoryId = int.tryParse(id);
    if (categoryId == null) {
      return Response(400,
          body: jsonEncode({'message': 'ID không hợp lệ'}),
          headers: {'content-type': 'application/json'});
    }

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final name = body['name']?.toString().trim() ?? '';
    final description = body['description']?.toString();
    final price = double.tryParse(body['price'].toString());
    final emoji = (body['emoji']?.toString().trim().isNotEmpty ?? false)
        ? body['emoji'].toString().trim()
        : '🔑';
    final isActive = (body['is_active'] as num?)?.toInt() ?? 1;

    if (name.isEmpty || price == null || price <= 0) {
      return Response(400,
          body: jsonEncode({'message': 'Dữ liệu không hợp lệ'}),
          headers: {'content-type': 'application/json'});
    }

    final ok = db.updateCategory(
      id: categoryId,
      name: name,
      description: description,
      price: price,
      emoji: emoji,
      isActive: isActive,
    );

    if (!ok) {
      return Response.notFound(
        jsonEncode({'message': 'Không tìm thấy danh mục'}),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'content-type': 'application/json'},
    );
  });

  router.delete('/<id>', (Request request, String id) {
    final categoryId = int.tryParse(id);
    if (categoryId == null) {
      return Response(400,
          body: jsonEncode({'message': 'ID không hợp lệ'}),
          headers: {'content-type': 'application/json'});
    }

    final ok = db.deleteCategory(categoryId);
    if (!ok) {
      return Response(400,
          body: jsonEncode({'message': 'Không thể xóa danh mục đã có tài khoản bán'}),
          headers: {'content-type': 'application/json'});
    }

    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}

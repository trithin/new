import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:telegram_account_shop_bot/config.dart';

Router authRoutes() {
  final router = Router();

  router.post('/login', (Request request) async {
    final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final username = payload['username']?.toString() ?? '';
    final password = payload['password']?.toString() ?? '';

    final inputHash = sha256.convert(utf8.encode(password)).toString();
    final expectedHash = sha256.convert(utf8.encode(Config.adminPassword)).toString();

    if (username != Config.adminUsername || inputHash != expectedHash) {
      return Response.forbidden(
        jsonEncode({'message': 'Sai tài khoản hoặc mật khẩu'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final token = JWT({
      'sub': 'admin',
      'username': username,
      'iat': DateTime.now().millisecondsSinceEpoch,
    }).sign(SecretKey(Config.jwtSecret), expiresIn: const Duration(hours: 12));

    return Response.ok(
      jsonEncode({'token': token}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}

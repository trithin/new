import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:telegram_account_shop_bot/config.dart';
import 'package:telegram_account_shop_bot/database/database.dart';
import 'package:telegram_account_shop_bot/server/routes/account_routes.dart';
import 'package:telegram_account_shop_bot/server/routes/auth_routes.dart';
import 'package:telegram_account_shop_bot/server/routes/category_routes.dart';
import 'package:telegram_account_shop_bot/server/routes/user_routes.dart';

Middleware jwtMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      if (request.url.path == 'auth/login') {
        return inner(request);
      }

      final auth = request.headers[HttpHeaders.authorizationHeader] ?? '';
      if (!auth.startsWith('Bearer ')) {
        return Response.forbidden(
          jsonEncode({'message': 'Thiếu token'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final token = auth.replaceFirst('Bearer ', '').trim();
      try {
        final verified = JWT.verify(token, SecretKey(Config.jwtSecret));
        return inner(request.change(context: {'jwt': verified.payload}));
      } catch (_) {
        return Response.forbidden(
          jsonEncode({'message': 'Token không hợp lệ'}),
          headers: {'content-type': 'application/json'},
        );
      }
    };
  };
}

Future<void> runServer(AppDatabase db) async {
  final api = Router()
    ..mount('/auth/', authRoutes().call)
    ..mount('/categories/', categoryRoutes(db).call)
    ..mount('/accounts/', accountRoutes(db).call)
    ..mount('/users/', userRoutes(db).call)
    ..get('/stats', (Request request) {
      return Response.ok(
        jsonEncode(db.getStats()),
        headers: {'content-type': 'application/json'},
      );
    });

  final staticHandler = createStaticHandler(
    'web',
    defaultDocument: 'index.html',
    listDirectories: false,
    useHeaderBytesForContentType: true,
  );

  final root = Router()
    ..mount(
      '/api/',
      Pipeline()
          .addMiddleware(logRequests())
          .addMiddleware(jwtMiddleware())
          .addHandler(api.call),
    )
    ..get('/healthz', (Request request) => Response.ok('ok'))
    ..mount('/', staticHandler);

  final server = await io.serve(
    root.call,
    InternetAddress.anyIPv4,
    Config.serverPort,
  );

  print('HTTP server chạy tại http://${server.address.host}:${server.port}');
  await Completer<void>().future;
}

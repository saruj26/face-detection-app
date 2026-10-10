import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glasses_tryon/core/api_config.dart';
import 'package:glasses_tryon/models/glasses.dart';
import 'package:glasses_tryon/services/glasses_api.dart';
import 'package:glasses_tryon/services/glasses_repository.dart';

/// Minimal fake transport: routes request paths to canned responses.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);

  final Map<String, (int, Object?)> routes;
  final requests = <RequestOptions>[];
  bool failConnection = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failConnection) {
      throw DioException.connectionError(requestOptions: options, reason: 'refused');
    }
    final route = routes[options.path];
    if (route == null) {
      return ResponseBody.fromString('{"detail":"Not Found"}', 404, headers: _json);
    }
    return ResponseBody.fromString(jsonEncode(route.$2), route.$1, headers: _json);
  }

  static const _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> glassesJson(int id, String name) => {
      'id': id,
      'name': name,
      'category': 'Round',
      'description': 'desc',
      'price': 89.5,
      'currency': 'USD',
      'catalogue_image_url': 'http://10.0.2.2:8000/static/glasses/r_catalogue.png',
      'transparent_overlay_url': 'http://10.0.2.2:8000/static/glasses/r_overlay.png',
      'fit_metadata': {
        'image_width': 1000,
        'image_height': 440,
        'anchor_x': 0.5,
        'anchor_y': 0.45,
        'eye_span_ratio': 0.29,
        'default_scale': 1.0,
      },
      'created_at': '2026-10-10T16:08:44Z',
    };

(GlassesApi, FakeAdapter) makeApi(Map<String, (int, Object?)> routes) {
  final dio = GlassesApi.createDio('http://10.0.2.2:8000');
  final adapter = FakeAdapter(routes);
  dio.httpClientAdapter = adapter;
  return (GlassesApi(dio), adapter);
}

const bundled = '''
[{"slug":"a","name":"Offline A","category":"Aviator","description":"d","price":10,"currency":"USD",
  "catalogue_image_url":"/static/glasses/a_catalogue.png","transparent_overlay_url":"/static/glasses/a_overlay.png",
  "fit_metadata":{"image_width":1000,"image_height":440,"eye_span_ratio":0.3}}]
''';

void main() {
  group('GlassesApi', () {
    test('GET /glasses parses items', () async {
      final (api, adapter) = makeApi({
        '/glasses': (200, {'items': [glassesJson(1, 'Round Wire'), glassesJson(2, 'Other')], 'total': 2}),
      });
      final items = await api.fetchGlasses();
      expect(items.map((g) => g.name), ['Round Wire', 'Other']);
      final g = items.first;
      expect(g.price, 89.5);
      expect(g.formattedPrice, r'$89.50');
      expect(g.fit.eyeSpanRatio, 0.29);
      expect(g.fit.anchorY, 0.45);
      expect(g.overlayImageUrl, endsWith('r_overlay.png'));
      expect(adapter.requests.single.uri.toString(), 'http://10.0.2.2:8000/glasses');
    });

    test('category filter is sent as a query parameter', () async {
      final (api, adapter) = makeApi({'/glasses': (200, {'items': [], 'total': 0})});
      await api.fetchGlasses(category: 'Round');
      expect(adapter.requests.single.queryParameters, {'category': 'Round'});
    });

    test('GET /glasses/{id}', () async {
      final (api, _) = makeApi({'/glasses/7': (200, glassesJson(7, 'Seven'))});
      expect((await api.fetchGlassesById(7)).name, 'Seven');
    });

    test('404 becomes a not-found ApiException', () async {
      final (api, _) = makeApi({});
      await expectLater(
        api.fetchGlassesById(99),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', isTrue)),
      );
    });

    test('503 explains the database is unavailable', () async {
      final (api, _) = makeApi({'/health': (503, {'status': 'degraded', 'database': 'unavailable'})});
      await expectLater(
        api.checkHealth(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('database'))),
      );
    });

    test('connection errors produce a helpful message with the URL', () async {
      final (api, adapter) = makeApi({});
      adapter.failConnection = true;
      await expectLater(
        api.fetchGlasses(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('10.0.2.2:8000'))),
      );
    });

    test('malformed payload is reported, not crashed on', () async {
      final (api, _) = makeApi({
        '/glasses': (200, {'items': [{'id': 'not-a-number'}]}),
      });
      await expectLater(api.fetchGlasses(), throwsA(isA<ApiException>()));
    });

    test('health ok', () async {
      final (api, _) = makeApi({'/health': (200, {'status': 'ok', 'database': 'ok'})});
      expect(await api.checkHealth(), isTrue);
    });
  });

  group('GlassesRepository', () {
    test('uses API data when available', () async {
      final (api, _) = makeApi({
        '/glasses': (200, {'items': [glassesJson(1, 'Live')], 'total': 1}),
      });
      final result = await GlassesRepository(api, loadAsset: (_) async => bundled).loadCatalogue();
      expect(result.isOffline, isFalse);
      expect(result.items.single.name, 'Live');
    });

    test('falls back to the bundled catalogue when the API is unreachable', () async {
      final (api, adapter) = makeApi({});
      adapter.failConnection = true;
      final result = await GlassesRepository(api, loadAsset: (_) async => bundled).loadCatalogue();
      expect(result.isOffline, isTrue);
      expect(result.offlineReason, isNotEmpty);
      final g = result.items.single;
      expect(g.id, 1);
      expect(g.overlayImageUrl, 'assets/glasses/a_overlay.png');
      expect(g.catalogueImageUrl, 'assets/glasses/a_catalogue.png');
    });

    test('with no backend configured the bundled catalogue is used without a warning', () async {
      final dio = GlassesApi.createDio('');
      final adapter = FakeAdapter({});
      dio.httpClientAdapter = adapter;
      final result = await GlassesRepository(GlassesApi(dio), loadAsset: (_) async => bundled).loadCatalogue();
      expect(result.isOffline, isTrue);
      expect(result.offlineReason, isNull);
      expect(adapter.requests, isEmpty);
    });

    test('loadById falls back to cached item on network error but not on 404', () async {
      final cached = Glasses.fromJson(glassesJson(3, 'Cached'));
      final (api, adapter) = makeApi({});
      final repo = GlassesRepository(api, loadAsset: (_) async => bundled);
      await expectLater(repo.loadById(3, fallback: [cached]), throwsA(isA<ApiException>()));
      adapter.failConnection = true;
      expect((await repo.loadById(3, fallback: [cached])).name, 'Cached');
    });
  });

  group('ApiConfig', () {
    test('normalize', () {
      expect(ApiConfig.normalize(' 192.168.1.20:8000/ '), 'http://192.168.1.20:8000');
      expect(ApiConfig.normalize('https://api.example.com//'), 'https://api.example.com');
    });

    test('isValid', () {
      expect(ApiConfig.isValid('http://10.0.2.2:8000'), isTrue);
      expect(ApiConfig.isValid(''), isFalse);
    });
  });

  test('FitMetadata clamps absurd eye span ratios', () {
    final fit = FitMetadata.fromJson({'image_width': 10, 'image_height': 5, 'eye_span_ratio': 0});
    expect(fit.eyeSpanRatio, 0.1);
  });

  test('formatPrice', () {
    expect(formatPrice(5, 'EUR'), '€5.00');
    expect(formatPrice(5, 'JPY'), '5.00 JPY');
  });
}

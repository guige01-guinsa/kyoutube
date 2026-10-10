import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/features/shopping/data/coupang_partners_repository.dart';

void main() {
  CoupangPartnersRepository repository(
      Future<http.Response> Function(http.Request) send) {
    final client = SupabaseClient('https://example.test', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(send));
    addTearDown(client.dispose);
    return CoupangPartnersRepository(client);
  }

  http.Response response(Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status,
          headers: {'content-type': 'application/json'});

  test('search calls the protected function and parses product metadata',
      () async {
    final repo = repository((req) async {
      expect(req.url.path, '/functions/v1/coupang_partners');
      expect(jsonDecode(req.body), {'action': 'search', 'keyword': '간장'});
      return response({
        'items': [
          {
            'productId': '123',
            'title': '간장 1L',
            'productUrl': 'https://www.coupang.com/vp/products/123',
            'price': 5000,
            'imageUrl':
                'https://image8.coupangcdn.com/image/product/ganjang.jpg'
          }
        ]
      });
    });
    final items = await repo.search(' 간장 ');
    expect(items.single.id, '123');
    expect(items.single.price, 5000);
    expect(items.single.imageUrl,
        'https://image8.coupangcdn.com/image/product/ganjang.jpg');
  });
  test('deeplink preserves options and rejects untrusted results', () async {
    var calls = 0;
    const url =
        'https://www.coupang.com/vp/products/123?itemId=4&vendorItemId=5';
    final repo = repository((req) async {
      calls++;
      expect(jsonDecode(req.body), {'action': 'deeplink', 'url': url});
      return response({
        'link': calls == 1
            ? 'https://link.coupang.com/a/Issued123'
            : 'https://evil.test'
      });
    });
    expect(await repo.deeplink(url), 'https://link.coupang.com/a/Issued123');
    await expectLater(
        repo.deeplink(url), throwsA(isA<CoupangPartnersException>()));
    await expectLater(repo.deeplink('https://evil.test'),
        throwsA(isA<CoupangPartnersException>()));
    expect(calls, 2);
  });
  test(
      'function error codes remain actionable without exposing response details',
      () async {
    final repo =
        repository((_) async => response({'error': 'admin_mfa_required'}, 403));
    await expectLater(
        repo.search('간장'),
        throwsA(isA<CoupangPartnersException>()
            .having((e) => e.code, 'code', 'admin_mfa_required')));
  });
  test('malformed search response is rejected', () async {
    final repo = repository((_) async => response({
          'items': [
            {
              'productId': '123',
              'title': 'wrong',
              'productUrl': 'https://www.coupang.com.evil/vp/products/123'
            }
          ]
        }));
    await expectLater(
        repo.search('간장'), throwsA(isA<CoupangPartnersException>()));
  });
  test('off-domain product images are omitted', () async {
    final repo = repository((_) async => response({
          'items': [
            {
              'productId': '123',
              'title': '간장',
              'productUrl': 'https://www.coupang.com/vp/products/123',
              'imageUrl': 'https://example.test/image.jpg'
            }
          ]
        }));
    expect((await repo.search('간장')).single.imageUrl, isNull);
  });
}

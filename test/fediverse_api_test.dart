import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumpun/fediverse_api.dart';

void main() {
  test('normalizes instance URLs and sends authenticated timelines', () async {
    late Uri requested;
    late Map<String, String> headers;
    final api = FediverseApi('social.example/', client: MockClient((request) async {
      requested = request.url;
      headers = request.headers;
      return http.Response(jsonEncode([{'id': '1'}]), 200);
    }));
    addTearDown(api.close);
    api.accessToken = 'test-token';

    final statuses = await api.timeline(type: 'home', limit: 10);

    expect(requested.toString(), 'https://social.example/api/v1/timelines/home?limit=10');
    expect(headers['Authorization'], 'Bearer test-token');
    expect(statuses.single['id'], '1');
  });

  test('builds an authorization URL with exact redirect and state', () {
    final api = FediverseApi('https://social.example');
    addTearDown(api.close);
    final uri = api.authorizationUri(clientId: 'client-id',
        redirectUri: 'http://127.0.0.1:1234/oauth/callback', state: 'csrf-state');
    expect(uri.path, '/oauth/authorize');
    expect(uri.queryParameters, {
      'response_type': 'code',
      'client_id': 'client-id',
      'redirect_uri': 'http://127.0.0.1:1234/oauth/callback',
      'scope': 'read write follow',
      'state': 'csrf-state',
    });
  });

  test('registers app and exchanges an authorization code', () async {
    final requests = <http.Request>[];
    final api = FediverseApi('social.example', client: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v1/apps') {
        return http.Response(jsonEncode({'client_id': 'id', 'client_secret': 'secret'}), 200);
      }
      return http.Response(jsonEncode({'access_token': 'token'}), 200);
    }));
    addTearDown(api.close);
    const redirect = 'http://127.0.0.1:4567/oauth/callback';

    final app = await api.registerApp(redirect);
    final token = await api.exchangeCode(clientId: app['client_id'] as String,
        clientSecret: app['client_secret'] as String, code: 'auth-code', redirectUri: redirect);

    expect(jsonDecode(requests.first.body)['redirect_uris'], redirect);
    expect(jsonDecode(requests.last.body), {
      'grant_type': 'authorization_code', 'client_id': 'id', 'client_secret': 'secret',
      'redirect_uri': redirect, 'code': 'auth-code',
    });
    expect(token, 'token');
    expect(api.accessToken, 'token');
  });

  test('requests public feeds and remote account profiles', () async {
    final requests = <http.Request>[];
    final api = FediverseApi('social.example', client: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v1/accounts/lookup') {
        return http.Response(jsonEncode({'id': '7'}), 200);
      }
      return http.Response(jsonEncode([]), 200);
    }));
    addTearDown(api.close);

    await api.timeline(type: 'public', local: true);
    await api.timeline(type: 'public', local: false);
    final account = await api.lookupAccount('person@remote.example');
    await api.accountStatuses(account['id'] as String);

    expect(requests[0].url.queryParameters['local'], 'true');
    expect(requests[1].url.queryParameters['local'], 'false');
    expect(requests[2].url.queryParameters['acct'], 'person@remote.example');
    expect(requests[3].url.path, '/api/v1/accounts/7/statuses');
  });

  test('rejects malformed instance URLs', () {
    expect(() => FediverseApi('https://user:secret@server.example'),
        throwsFormatException);
  });

  test('rejects token responses without an access token', () async {
    final api = FediverseApi('social.example', client: MockClient((_) async =>
        http.Response('{}', 200)));
    addTearDown(api.close);
    expect(() => api.exchangeCode(clientId: 'id', clientSecret: 'secret',
        code: 'code', redirectUri: 'http://127.0.0.1/callback'), throwsFormatException);
  });

  test('surfaces server OAuth errors', () async {
    final api = FediverseApi('social.example', client: MockClient((_) async =>
        http.Response('denied', 401)));
    addTearDown(api.close);
    expect(() => api.exchangeCode(clientId: 'id', clientSecret: 'secret',
        code: 'code', redirectUri: 'http://127.0.0.1/callback'),
        throwsA(isA<FediverseException>()));
  });

  test('reads a relationship and posts follow/unfollow', () async {
    final requests = <http.Request>[];
    final api = FediverseApi('social.example', client: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v1/accounts/relationships') {
        return http.Response(jsonEncode([{'id': '7', 'following': true}]), 200);
      }
      return http.Response(jsonEncode({'id': '7', 'following': false, 'requested': true}), 200);
    }));
    addTearDown(api.close);
    final rel = await api.relationship('7');
    expect(rel['following'], true);
    expect(requests.single.url.queryParameters['id[]'], '7');
    final result = await api.follow('7', follow: false);
    expect(result['requested'], true);
    expect(requests.last.url.path, '/api/v1/accounts/7/unfollow');
    expect(requests.last.method, 'POST');
  });

  test('filters notifications and authorizes follow requests', () async {
    final requests = <http.Request>[];
    final api = FediverseApi('social.example', client: MockClient((request) async {
      requests.add(request);
      if (request.url.path.contains('/follow_requests/')) {
        return http.Response(jsonEncode({'id': '9'}), 200);
      }
      if (request.url.path.contains('/api/v2/search')) {
        return http.Response(jsonEncode({'accounts': [], 'hashtags': [], 'statuses': []}), 200);
      }
      return http.Response(jsonEncode([]), 200);
    }));
    addTearDown(api.close);

    await api.notifications(types: ['mention']);
    await api.followRequestAuthorize('9', authorize: true);
    await api.search('tag', type: 'hashtags');

    expect(requests[0].url.queryParameters['types[]'], 'mention');
    expect(requests[1].url.path, '/api/v1/follow_requests/9/authorize');
    expect(requests[2].url.queryParameters['type'], 'hashtags');
  });

  test('posts status with sensitive media and poll options', () async {
    late Map<String, dynamic> body;
    final api = FediverseApi('social.example', client: MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'id': '101'}), 200);
    }));
    addTearDown(api.close);

    await api.post('Hello', sensitive: true, poll: {'options': ['A', 'B'], 'expires_in': 86400});

    expect(body['status'], 'Hello');
    expect(body['sensitive'], 'true');
    expect(body['poll'], {'options': ['A', 'B'], 'expires_in': 86400});
  });

  test('fetches custom emojis from server', () async {
    final api = FediverseApi('social.example', client: MockClient((request) async {
      expect(request.url.path, '/api/v1/custom_emojis');
      return http.Response(jsonEncode([
        {'shortcode': 'blobcat', 'url': 'https://social.example/blobcat.png'}
      ]), 200);
    }));
    addTearDown(api.close);

    final emojis = await api.customEmojis();
    expect(emojis.length, 1);
    expect(emojis.first['shortcode'], 'blobcat');
  });

  test('updates media description via PUT and formats JSON error messages', () async {
    late String method;
    late Map<String, dynamic> body;
    final api = FediverseApi('social.example', client: MockClient((request) async {
      method = request.method;
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'id': 'm1'}), 200);
    }));
    addTearDown(api.close);

    await api.updateMedia('m1', description: 'A cat');
    expect(method, 'PUT');
    expect(body, {'description': 'A cat'});
    expect(
      const FediverseException(422, '{"error":"Validation failed"}').toString(),
      'Fediverse API error (422): Validation failed',
    );
  });

  test('registers and deletes FCM push subscription', () async {
    final methods = <String>[];
    final paths = <String>[];
    final api = FediverseApi('social.example', client: MockClient((request) async {
      methods.add(request.method);
      paths.add(request.url.path);
      return http.Response(jsonEncode({'id': 'push-1', 'endpoint': 'https://fcm.example/1'}), 200);
    }));
    addTearDown(api.close);

    final sub = await api.registerPushSubscription(endpoint: 'https://fcm.example/1');
    expect(sub['id'], 'push-1');
    await api.deletePushSubscription();
    expect(methods, ['POST', 'DELETE']);
    expect(paths, ['/api/v1/push/subscription', '/api/v1/push/subscription']);
  });
}

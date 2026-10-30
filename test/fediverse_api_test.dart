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
}

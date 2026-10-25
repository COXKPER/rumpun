import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun/oauth_callback.dart';

void main() {
  test('only accepts a code for matching OAuth state', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final result = receiveOAuthCode(server, 'expected');
    final client = HttpClient();
    addTearDown(client.close);

    final wrong = await client.getUrl(Uri.parse(
        'http://127.0.0.1:${server.port}/oauth/callback?code=bad&state=wrong'));
    final wrongResponse = await wrong.close();
    expect(wrongResponse.statusCode, HttpStatus.badRequest);
    await wrongResponse.drain<void>();

    final valid = await client.getUrl(Uri.parse(
        'http://127.0.0.1:${server.port}/oauth/callback?code=good&state=expected'));
    final validResponse = await valid.close();
    expect(validResponse.statusCode, HttpStatus.ok);
    expect(await result, 'good');
  });

  test('reports authorization denial after state verification', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final result = receiveOAuthCode(server, 'expected');
    final client = HttpClient();
    addTearDown(client.close);

    final denied = await client.getUrl(Uri.parse(
        'http://127.0.0.1:${server.port}/oauth/callback?error=access_denied&state=expected'));
    await (await denied.close()).drain<void>();
    await expectLater(result, throwsA(isA<StateError>()));
  });
}

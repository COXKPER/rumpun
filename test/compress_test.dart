import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun/compress.dart';

void main() {
  test('round-trips a status map', () {
    final status = {
      'id': '1',
      'content': '<p>hello</p>' * 40,
      'account': {'acct': 'someone@example.social'},
    };
    final decoded = decodeCache(encodeCache(status));
    expect(decoded, isA<Map<String, dynamic>>());
    expect((decoded as Map<String, dynamic>)['id'], '1');
    expect(decoded['account'], {'acct': 'someone@example.social'});
  });

  test('reads legacy plain-JSON rows written by older builds', () {
    expect(decodeCache('{"id":"9"}'), {'id': '9'});
    expect(decodeCache('[{"id":"9"}]'), [
      {'id': '9'}
    ]);
  });

  test('returns null instead of throwing on corrupt rows', () {
    expect(decodeCache('not-a-payload'), isNull);
    expect(decodeCache('{broken'), isNull);
  });
}

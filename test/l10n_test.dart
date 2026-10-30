import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun/l10n.dart';

void main() {
  test('resolves legacy, bcp47 and system tags to a table name', () {
    expect(normalizeTag('en'), 'en-us');
    expect(normalizeTag('en_US'), 'en-us');
    expect(normalizeTag('en-GB'), 'en-gb');
    expect(normalizeTag('id_ID'), 'id-id');
    expect(normalizeTag('ja'), 'ja-jp');
    expect(normalizeTag('ja-JP'), 'ja-jp');
    // Unknown languages fall back to English rather than an empty table.
    expect(normalizeTag('xx-YY'), 'en-us');
  });

  test('falls back to the key when no table is loaded', () {
    expect(t('Home'), 'Home');
  });
}

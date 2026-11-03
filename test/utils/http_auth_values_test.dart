import 'package:PiliPlus/utils/http_auth_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cookie normalization accepts adapter lists on retries', () {
    expect(cookieHeaderValue(null), '');
    expect(cookieHeaderValue('a=1; b=2'), 'a=1; b=2');
    expect(cookieHeaderValue(<dynamic>['a=1', 'b=2']), 'a=1; b=2');
    expect(cookieHeaderValue(<dynamic>['a=1', null, '']), 'a=1');
    expect(cookieHeaderValue(123), '');
  });
}

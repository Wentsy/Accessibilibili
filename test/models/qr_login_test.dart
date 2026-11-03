import 'package:flutter_test/flutter_test.dart';
import 'package:PiliPlus/models/login/qr_login.dart';

Map<String, Object> payload({bool nested = false}) => {
  'code': 0,
  'message': 'OK',
  'data': {
    if (nested)
      'token_info': {
        'access_token': 'app-secret',
        'refresh_token': 'refresh-secret',
        'mid': 123,
      }
    else ...{
      'access_token': 'app-secret',
      'refresh_token': 'refresh-secret',
      'mid': 123,
    },
    'cookie_info': {
      'cookies': [
        {'name': 'DedeUserID', 'value': '123'},
        {'name': 'SESSDATA', 'value': 'session-secret'},
        {'name': 'bili_jct', 'value': 'csrf-secret'},
      ],
    },
  },
};

void main() {
  test('accepts both flat and nested App token replies', () {
    for (final nested in [false, true]) {
      final reply = QrLoginReply.fromJson(payload(nested: nested));
      expect(reply.canSave, isTrue);
      expect(reply.accessToken, 'app-secret');
      expect(reply.cookies, hasLength(3));
    }
  });

  test('Cookie-only success cannot be mistaken for App authorization', () {
    final json = payload();
    (json['data'] as Map).remove('access_token');
    final reply = QrLoginReply.fromJson(json);
    expect(reply.canSave, isFalse);
    expect(reply.credentialError, contains('App'));
  });

  test('missing CSRF or mismatched account prevents saving', () {
    final json = payload();
    (((json['data'] as Map)['cookie_info'] as Map)['cookies'] as List)
        .removeLast();
    expect(QrLoginReply.fromJson(json).credentialError, contains('bili_jct'));
    final mismatch = payload(nested: true);
    ((mismatch['data'] as Map)['token_info'] as Map)['mid'] = 456;
    expect(QrLoginReply.fromJson(mismatch).credentialError, contains('不一致'));
  });

  test(
    'wait, expired, rejected and malformed replies remain distinguishable',
    () {
      for (final code in [86039, 86090, 86101]) {
        expect(QrLoginReply.fromJson({'code': code}).waiting, isTrue);
      }
      expect(QrLoginReply.fromJson({'code': 86038}).expired, isTrue);
      final rejected = QrLoginReply.fromJson({
        'code': -999,
        'message': '不支持此 App 登录',
      });
      expect(rejected.waiting, isFalse);
      expect(rejected.canSave, isFalse);
      expect(rejected.diagnostic, contains('-999'));
      expect(rejected.diagnostic, contains('不支持此 App 登录'));
      for (final value in [
        null,
        '<html>error</html>',
        {},
        {'code': 0, 'data': []},
      ]) {
        expect(QrLoginReply.fromJson(value).canSave, isFalse);
      }
    },
  );

  test('copyable diagnostic excludes credentials, UID and URLs', () {
    final reply = QrLoginReply.fromJson(payload(nested: true));
    for (final secret in [
      'app-secret',
      'refresh-secret',
      'session-secret',
      'csrf-secret',
      '123',
    ]) {
      expect(reply.diagnostic, isNot(contains(secret)));
    }
    expect(
      QrLoginReply.safeMessage('SESSDATA=private; auth_code=private'),
      isNot(contains('private')),
    );
    expect(
      QrLoginReply.safeMessage('https://example.com/?q=private'),
      isNot(contains('private')),
    );
    expect(
      QrLoginReply.safeMessage('0123456789abcdef0123456789abcdef'),
      isNot(contains('012345')),
    );
  });
}

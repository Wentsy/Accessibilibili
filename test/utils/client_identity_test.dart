import 'dart:convert';

import 'package:PiliPlus/utils/client_identity.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String expectedSignature(Map<String, dynamic> params, String secret) {
  final keys = params.keys.where((key) => key != 'sign').toList()..sort();
  final query = keys.map((key) =>
      '${Uri.encodeComponent(key)}=${Uri.encodeComponent(params[key].toString())}'
  ).join('&');
  return md5.convert(utf8.encode(query + secret)).toString();
}

void main() {
  test('general API signing replaces stale Android identity and signature', () {
    final params = <String, dynamic>{
      'access_key': 'test-token',
      'mobi_app': 'android',
      'platform': 'android',
      'device': 'android',
      'build': 8430300,
      'version': '8.43.0',
      'statistics': '{"appId":1,"platform":3}',
      'sign': 'stale-signature',
      'page': 2,
    };
    InternationalClient.sign(params, passport: false, buvid: 'test-buvid');
    expect(params['access_key'], 'test-token');
    expect(params['page'], 2);
    expect(params['appkey'], InternationalClient.appKey);
    expect(params['mobi_app'], 'iphone_i');
    expect(params['platform'], 'ios');
    expect(params['device'], 'phone');
    expect(params['build'], InternationalClient.build.toString());
    expect(params.containsKey('statistics'), isFalse);
    expect(params['sign'], expectedSignature(params, InternationalClient.appSecret));
    InternationalClient.sign(params, passport: false, buvid: 'test-buvid');
    expect(params['sign'], expectedSignature(params, InternationalClient.appSecret));
  });

  test('Passport signing uses a different key and the account device', () {
    final params = <String, dynamic>{'local_id': 'anonymous-device'};
    InternationalClient.sign(params, passport: true, buvid: 'account-device');
    expect(params['appkey'], InternationalClient.passportKey);
    expect(params['local_id'], 'account-device');
    expect(params['buvid'], 'account-device');
    expect(params['sign'],
        expectedSignature(params, InternationalClient.passportSecret));
  });

  test('header casing cannot retain a conflicting client identity', () {
    final headers = <String, dynamic>{
      'User-Agent': 'old',
      'user-agent': 'also-old',
      'App-Key': 'android',
      'referer': 'https://www.bilibili.com/',
    };
    InternationalClient.applyHeaders(headers);
    expect(headers['user-agent'], InternationalClient.userAgent);
    expect(headers['app-key'], 'iphone_i');
    expect(headers.containsKey('User-Agent'), isFalse);
    expect(headers.containsKey('App-Key'), isFalse);
    expect(headers['referer'], 'https://www.bilibili.com/');
  });
}

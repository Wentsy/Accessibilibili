import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/passport_refresh.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

Map reply({int mid = 123}) => {
  'code': 0,
  'data': {
    'token_info': {'mid': mid, 'access_token': 'new-access',
      'refresh_token': 'new-refresh'},
    'cookie_info': {'cookies': [
      {'name': 'DedeUserID', 'value': '$mid'},
      {'name': 'SESSDATA', 'value': 'new-session'},
      {'name': 'bili_jct', 'value': 'new-csrf'},
    ]},
  },
};

void main() {
  late Directory dir;
  late LoginAccount account;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('passport-refresh-');
    Hive.init(dir.path);
    GStorage.regAdapter();
    Accounts.account = await Hive.openBox<LoginAccount>('account');
  });
  setUp(() async {
    await Accounts.account.clear();
    account = LoginAccount(BiliCookieJar.fromJson({
      'DedeUserID': '123', 'SESSDATA': 'old-session', 'bili_jct': 'old-csrf',
    }), 'old-access', 'old-refresh', null, 'test-buvid', true);
    await account.onChange();
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('concurrent requests share a refresh and confirm OLD credentials', () async {
    final gate = Completer<void>();
    final calls = <String>[];
    Future<Map?> send(String path, Map<String, dynamic> params, bool post) async {
      calls.add(path);
      if (path.endsWith('/info')) {
        await gate.future;
        return {'code': 0, 'data': {'mid': 123, 'refresh': true}};
      }
      if (path.endsWith('/timestamp')) {
        return {'code': 0, 'data': {'timestamp': 1700000000}};
      }
      if (path.endsWith('/refresh_token')) return reply();
      expect(account.accessKey, 'new-access');
      expect(Accounts.account.get('123')!.refresh, 'new-refresh');
      expect(params['access_key'], 'old-access');
      expect(params['session'], 'old-session');
      expect(params['sts'], '1700000000');
      return {'code': 0};
    }
    final first = PassportRefresh.ensureFresh(account, transport: send);
    final second = PassportRefresh.ensureFresh(account, transport: send);
    gate.complete();
    await Future.wait([first, second]);
    expect(calls.where((p) => p.endsWith('/refresh_token')).length, 1);
    expect(account.csrf, 'new-csrf');
    expect(account.pendingRefreshConfirmation, isNull);
  });

  test('wrong account reply leaves original session untouched', () async {
    await PassportRefresh.ensureFresh(account, transport: (path, params, post) async {
      if (path.endsWith('/info')) return {'code': -101};
      if (path.endsWith('/timestamp')) {
        return {'code': 0, 'data': {'timestamp': 1700000000}};
      }
      return reply(mid: 999);
    });
    expect(account.accessKey, 'old-access');
    expect(account.csrf, 'old-csrf');
    expect(account.pendingRefreshConfirmation, isNull);
  });

  test('logout during refresh cannot recreate account', () async {
    await PassportRefresh.ensureFresh(account, transport: (path, params, post) async {
      if (path.endsWith('/info')) return {'code': -101};
      if (path.endsWith('/timestamp')) {
        return {'code': 0, 'data': {'timestamp': 1700000000}};
      }
      await account.delete();
      return reply();
    });
    expect(Accounts.account.containsKey('123'), isFalse);
    expect(account.accessKey, 'old-access');
  });

  test('failed confirmation keeps new credentials and retries only confirmation', () async {
    var now = DateTime(2026);
    var confirmations = 0;
    var rotations = 0;
    Future<Map?> send(String path, Map<String, dynamic> params, bool post) async {
      if (path.endsWith('/info')) {
        return {'code': 0, 'data': {'mid': 123, 'refresh': rotations == 0}};
      }
      if (path.endsWith('/timestamp')) {
        return {'code': 0, 'data': {'timestamp': 1700000000}};
      }
      if (path.endsWith('/refresh_token')) { rotations++; return reply(); }
      confirmations++;
      return {'code': confirmations == 1 ? -500 : 0};
    }
    await PassportRefresh.ensureFresh(account, transport: send, clock: () => now);
    expect(account.accessKey, 'new-access');
    expect(account.pendingRefreshConfirmation, isNotNull);
    final restored = LoginAccount.fromJson(account.toJson()!);
    expect(restored.pendingRefreshConfirmation!['access_key'], 'old-access');
    now = now.add(const Duration(minutes: 11));
    await PassportRefresh.ensureFresh(account, transport: send, clock: () => now);
    expect(rotations, 1);
    expect(confirmations, 2);
    expect(account.pendingRefreshConfirmation, isNull);
  });

  test('network failures cool down without changing credentials', () async {
    var calls = 0;
    Future<Map?> send(String p, Map<String, dynamic> v, bool post) async {
      calls++;
      throw const SocketException('offline');
    }
    await PassportRefresh.ensureFresh(account, transport: send);
    await PassportRefresh.ensureFresh(account, transport: send);
    expect(calls, 1);
    expect(account.accessKey, 'old-access');
  });
}

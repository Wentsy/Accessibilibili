import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/grpc/bilibili/metadata.pb.dart';
import 'package:PiliPlus/grpc/bilibili/metadata/device.pb.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/accounts/grpc_headers.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

LoginAccount account(bool international) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'test-csrf'}),
  'test-access',
  'test-refresh',
  null,
  'test-buvid',
  international,
);

void main() {
  test('JSON backups preserve origin; old backups remain legacy', () {
    final json = account(true).toJson()!;
    expect(LoginAccount.fromJson(json).internationalPassport, isTrue);
    json.remove('internationalPassport');
    expect(LoginAccount.fromJson(json).internationalPassport, isFalse);
  });

  test('international IM metadata retains the token and login BUVID', () {
    final a = account(true);
    final headers = GrpcHeaders.newHeaders(a, internationalPassport: true);
    final metadata = Metadata.fromBuffer(
      base64Decode(headers['x-bili-metadata-bin']!),
    );
    final device = Device.fromBuffer(
      base64Decode(headers['x-bili-device-bin']!),
    );
    expect(metadata.accessKey, 'test-access');
    expect(metadata.buvid, 'test-buvid');
    expect(metadata.mobiApp, 'iphone_i');
    expect(metadata.platform, 'ios');
    expect(metadata.device, 'phone');
    expect(metadata.build, 68500200);
    expect(device.mobiApp, metadata.mobiApp);
    expect(device.platform, metadata.platform);
    expect(device.hasAppId(), isFalse);
    expect(headers['authorization'], 'identify_v1 test-access');

    final legacy = GrpcHeaders.newHeaders(a);
    final legacyMetadata = Metadata.fromBuffer(
      base64Decode(legacy['x-bili-metadata-bin']!),
    );
    expect(legacyMetadata.mobiApp, 'android_hd');
    expect(legacyMetadata.accessKey, 'test-access');
  });

  test('Hive persists both origins across closing and reopening', () async {
    final dir = await Directory.systemTemp.createTemp('passport-origin-test-');
    Hive.init(dir.path);
    GStorage.regAdapter();
    try {
      var box = await Hive.openBox<LoginAccount>('passport-test');
      await box.put('international', account(true));
      await box.put('legacy', account(false));
      await box.close();
      box = await Hive.openBox<LoginAccount>('passport-test');
      expect(box.get('international')!.internationalPassport, isTrue);
      expect(box.get('international')!.buvid, 'test-buvid');
      expect(box.get('legacy')!.internationalPassport, isFalse);
    } finally {
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });
}

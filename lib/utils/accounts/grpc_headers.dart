import 'dart:convert';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/bilibili/metadata.pb.dart';
import 'package:PiliPlus/grpc/bilibili/metadata/device.pb.dart';
import 'package:PiliPlus/grpc/bilibili/metadata/fawkes.pb.dart';
import 'package:PiliPlus/grpc/bilibili/metadata/locale.pb.dart';
import 'package:PiliPlus/grpc/bilibili/metadata/network.pb.dart' as network;
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/utils.dart';

abstract final class GrpcHeaders {
  static const _build = 2001100;
  static const _versionName = '2.0.1';
  static const _biliChannel = 'master';
  static const _mobiApp = 'android_hd';
  static const _device = 'android';

  static String get _traceId => Constants.traceId;
  static String get _sessionId => Utils.generateRandomString(8);

  static final Map<String, String> _base = {
    'grpc-encoding': 'gzip',
    'gzip-accept-encoding': 'gzip,identity',
    'user-agent': Constants.userAgent,
    'x-bili-gaia-vtoken': '',
    'x-bili-aurora-zone': '',
    'x-bili-trace-id': _traceId,
    'bili-http-engine': 'cronet',
    // 'te': 'trailers', // dio not supported
    'x-bili-network-bin': base64Encode(
      network.Network(type: network.NetworkType.WIFI).writeToBuffer(),
    ),
    'x-bili-locale-bin': base64Encode(
      Locale(
        cLocale: LocaleIds(language: 'zh', region: 'CN', script: 'Hans'),
        sLocale: LocaleIds(language: 'zh', region: 'CN', script: 'Hans'),
        timezone: 'Asia/Shanghai',
      ).writeToBuffer(),
    ),
    'x-bili-exps-bin': '',
  };

  static String get fawkes => base64Encode(
    FawkesReq(
      appkey: _mobiApp,
      env: 'prod',
      sessionId: _sessionId,
    ).writeToBuffer(),
  );

  static Map<String, String> newHeaders(
    Account account, {
    bool? internationalPassport,
  }) {
    internationalPassport ??=
        account is LoginAccount && account.internationalPassport;
    final mobiApp = internationalPassport ? 'iphone_i' : _mobiApp;
    final platform = internationalPassport ? 'ios' : _device;
    final device = internationalPassport ? 'phone' : _device;
    final build = internationalPassport ? 68500200 : _build;
    final channel = internationalPassport ? 'appstore' : _biliChannel;
    return {
      ..._base,
      if (account.accessKey != null)
        'authorization': 'identify_v1 ${account.accessKey}',
      if (internationalPassport)
        'user-agent': 'BiliApp/3.13.0 os/ios mobi_app/iphone_i build/68500200',
      'buvid': account.buvid,
      'x-bili-fawkes-req-bin': internationalPassport
          ? base64Encode(FawkesReq(
              appkey: mobiApp,
              env: 'prod',
              sessionId: _sessionId,
            ).writeToBuffer())
          : fawkes,
      'x-bili-device-bin': base64Encode(
        Device(
          // The international numeric app ID is not established by the IPA
          // evidence. Leave it unset instead of asserting Android HD's ID.
          appId: internationalPassport ? null : 5,
          build: build,
          buvid: account.buvid,
          mobiApp: mobiApp,
          platform: platform,
          device: internationalPassport ? device : null,
          channel: channel,
          brand: internationalPassport ? 'Apple' : _device,
          model: internationalPassport ? 'iPhone' : _device,
          osver: '15',
          versionName: internationalPassport ? '3.13.0' : _versionName,
        ).writeToBuffer(),
      ),
      'x-bili-metadata-bin': base64Encode(
        Metadata(
          accessKey: account.accessKey,
          mobiApp: mobiApp,
          device: device,
          build: build,
          channel: channel,
          buvid: account.buvid,
          platform: platform,
        ).writeToBuffer(),
      ),
    };
  }
}

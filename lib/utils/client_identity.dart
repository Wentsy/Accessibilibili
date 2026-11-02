import 'package:PiliPlus/utils/app_sign.dart';

/// App signing constants observed in com.bilibili.inter 3.13.0.
/// Passport and ordinary API credentials are deliberately separate.
abstract final class InternationalClient {
  static const appKey = '27eb53fc9058f8c3';
  static const appSecret = 'c2ed53a74eeefe3cf99fbd01d8c9c375';
  static const passportKey = '5ae412b53418aac5';
  static const passportSecret = '5b9cf6c9786efd204dcf0c1ce2d08436';
  static const build = 68500200;
  static const version = '3.13.0';
  static const userAgent =
      'BiliApp/3.13.0 os/ios mobi_app/iphone_i build/68500200';

  static void sign(
    Map<String, dynamic> params, {
    required bool passport,
    required String buvid,
  }) {
    params.remove('sign');
    // Do not carry Android's numeric app/platform statistics into iOS.
    params.remove('statistics');
    params.addAll({
      'mobi_app': 'iphone_i',
      'platform': 'ios',
      'build': build.toString(),
      'buvid': buvid,
    });
    const replacements = <String, Object>{
      'device': 'phone',
      'device_name': 'Accessibilibili',
      'device_platform': 'iOS',
      'channel': 'appstore',
      'version': version,
    };
    for (final entry in replacements.entries) {
      if (params.containsKey(entry.key)) params[entry.key] = entry.value;
    }
    if (params.containsKey('local_id')) params['local_id'] = buvid;
    if (params.containsKey('bili_local_id')) params['bili_local_id'] = buvid;
    if (params.containsKey('device_id')) params['device_id'] = buvid;
    AppSign.appSign(
      params,
      appkey: passport ? passportKey : appKey,
      appsec: passport ? passportSecret : appSecret,
    );
  }

  static void applyHeaders(Map<String, dynamic> headers) {
    // Dio callers use both User-Agent and user-agent; remove either spelling.
    headers.removeWhere((key, _) =>
        key.toLowerCase() == 'user-agent' ||
        key.toLowerCase() == 'app-key');
    headers.addAll({'user-agent': userAgent, 'app-key': 'iphone_i'});
  }
}

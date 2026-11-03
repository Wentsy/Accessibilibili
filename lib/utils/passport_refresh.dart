import 'dart:async';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/login/qr_login.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/utils/client_identity.dart';
import 'package:dio/dio.dart';

typedef PassportTransport = Future<Map?> Function(
  String path, Map<String, dynamic> params, bool post,
);

class _RefreshState {
  Future<void>? running;
  DateTime nextCheck = DateTime.fromMillisecondsSinceEpoch(0);
}

/// Automatic pre-dispatch refresh for the verified International Passport path.
/// Legacy/anonymous/Cookie-only accounts do not use this protocol.
abstract final class PassportRefresh {
  static final _states = Expando<_RefreshState>();

  static Future<void> ensureFresh(
    LoginAccount account, {
    PassportTransport? transport,
    DateTime Function()? clock,
  }) {
    if (!account.internationalPassport ||
        account.accessKey?.isNotEmpty != true ||
        account.refresh?.isNotEmpty != true || !account.isCurrent) {
      return Future.value();
    }
    final state = _states[account] ??= _RefreshState();
    if (state.running case final running?) return running;
    final now = clock ?? DateTime.now;
    if (now().isBefore(state.nextCheck)) return Future.value();
    // Cool down even after network/protocol errors; never spin on every request.
    state.nextCheck = now().add(const Duration(minutes: 10));
    final done = Completer<void>();
    state.running = done.future;
    () async {
      try {
        await _refresh(account, state, transport ?? _send, now);
      } catch (_) {
        // Retain the existing session. Never expose response bodies or tokens.
      } finally {
        state.running = null;
        done.complete();
      }
    }();
    return done.future;
  }

  static Map<String, dynamic> _params(LoginAccount account,
      [Map<String, dynamic> extra = const {}]) {
    final params = <String, dynamic>{
      'sdk_ver': '0.1.15',
      'actionKey': 'appkey',
      'device': 'phone',
      'local_id': account.buvid,
      'bili_local_id': account.buvid,
      'device_id': account.buvid,
      'device_name': 'Accessibilibili',
      'device_platform': 'iOS',
      ...extra,
    };
    InternationalClient.sign(params, passport: true, buvid: account.buvid);
    return params;
  }

  static Future<Map?> _send(
    String path, Map<String, dynamic> params, bool post,
  ) async {
    final options = Options(
      contentType: Headers.formUrlEncodedContentType,
      headers: {'user-agent': InternationalClient.userAgent},
      extra: {'account': const NoAccount(), 'noRetry': true, 'quietErrors': true},
      followRedirects: false,
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    );
    final url = 'https://passport.bilibili.com$path';
    final response = post
        ? await Request().post(url, data: params, options: options)
        : await Request().get(url, queryParameters: params, options: options);
    return response.data is Map ? response.data as Map : null;
  }

  static Future<bool> _confirm(LoginAccount account,
      PassportTransport send) async {
    final pending = account.pendingRefreshConfirmation;
    if (pending == null) return true;
    if (!account.isCurrent) return false;
    final response = await send('/x/passport-login/confirm/refresh',
        _params(account, pending), true);
    if (response?['code'] != 0 || !account.isCurrent) return false;
    account.pendingRefreshConfirmation = null;
    try {
      await account.onChange();
    } catch (_) {
      account.pendingRefreshConfirmation = pending;
      rethrow;
    }
    return true;
  }

  static Future<void> _refresh(LoginAccount account, _RefreshState state,
      PassportTransport send, DateTime Function() now) async {
    // A prior successful rotation must be confirmed before rotating again.
    if (!await _confirm(account, send) || !account.isCurrent) return;
    final oldAccess = account.accessKey!;
    final oldRefresh = account.refresh!;
    final info = await send('/x/passport-login/oauth2/info',
        _params(account, {'access_key': oldAccess}), false);
    if (!account.isCurrent || account.accessKey != oldAccess) return;
    final data = info?['data'];
    if (info?['code'] == 0 && data is Map) {
      final mid = data['mid'];
      if (mid != null && mid.toString() != account.mid.toString()) return;
      final expires = int.tryParse('${data['expires_in']}');
      final needsRefresh = data['refresh'] == true || data['refresh'] == 1 ||
          (expires != null && expires <= 300);
      if (!needsRefresh) {
        final seconds = expires == null ? 3600 : (expires - 300).clamp(60, 3600);
        state.nextCheck = now().add(Duration(seconds: seconds.toInt()));
        return;
      }
    } else if (info?['code'] != -101) {
      return;
    }

    final time = await send('/x/passport-login/timestamp',
        _params(account), false);
    final timeData = time?['data'];
    final sts = timeData is Map
        ? int.tryParse('${timeData['timestamp'] ?? timeData['ts']}')
        : null;
    if (time?['code'] != 0 || sts == null || sts <= 0 ||
        !account.isCurrent || account.accessKey != oldAccess) return;
    final session = account.cookieJar.toJson()['SESSDATA'];
    if (session == null || session.isEmpty) return;
    final response = await send('/x/passport-login/oauth2/refresh_token',
        _params(account, {
          'access_key': oldAccess, 'refresh_token': oldRefresh, 'sts': '$sts',
        }), true);
    if (!account.isCurrent || account.accessKey != oldAccess) return;
    final reply = QrLoginReply.fromJson(response);
    final confirmation = <String, dynamic>{
      'mid': '${account.mid}',
      'access_key': oldAccess,
      'refresh_token': oldRefresh,
      'session': session,
      'revoke_api': 'REFRESH_CONFIRM_REVOKE',
      'sts': '$sts',
    };
    if (!await account.installRefreshedSession(reply, confirmation)) return;
    if (identical(Accounts.main, account)) {
      try {
        await LoginUtils.setWebCookie(account);
      } catch (_) {
        // Native credentials are already durable; WebView sync is best effort.
      }
    }
    // If confirmation fails, keep the new session and durable pending action.
    if (await _confirm(account, send)) {
      state.nextCheck = now().add(const Duration(hours: 1));
    }
  }
}

/// TV/HD login replies can contain credentials at the top level or token_info.
/// Keep diagnostics separate from the payload: never copy tokens or QR URLs.
class QrLoginReply {
  final int? code;
  final String message;
  final Map? data;

  QrLoginReply.fromJson(Object? json)
    : code = json is Map && json['code'] is int ? json['code'] as int : null,
      message = safeMessage(json is Map ? json['message'] : null),
      data = json is Map && json['data'] is Map ? json['data'] as Map : null;

  bool get waiting => code == 86039 || code == 86090 || code == 86101;
  bool get expired => code == 86038;
  Map? get token =>
      data?['token_info'] is Map ? data!['token_info'] as Map : data;
  String? get accessToken => _nonEmpty(token?['access_token']);
  String? get refreshToken => _nonEmpty(token?['refresh_token']);
  List<Map<String, String>> get cookies {
    final info = data?['cookie_info'];
    final list = info is Map ? info['cookies'] : null;
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map && item['name'] is String && item['value'] is String)
          {'name': item['name'] as String, 'value': item['value'] as String},
    ];
  }

  String? get credentialError {
    if (accessToken == null) return '未收到 App 登录凭证';
    final values = {for (final c in cookies) c['name']!: c['value']!};
    for (final name in ['SESSDATA', 'bili_jct', 'DedeUserID']) {
      if (_nonEmpty(values[name]) == null) return '登录资料不完整：缺少 $name';
    }
    final mid = int.tryParse(values['DedeUserID']!);
    if (mid == null || mid <= 0) return '登录资料中的账号编号无效';
    final tokenMid = token?['mid'] ?? data?['mid'];
    if (tokenMid != null && tokenMid.toString() != mid.toString()) {
      return '登录凭证与 Cookie 的账号不一致';
    }
    return null;
  }

  bool get canSave => code == 0 && credentialError == null;

  String get diagnostic =>
      '阶段：扫码结果\n错误码：${code ?? "无"}\n消息：$message\n'
      'App 凭证：${accessToken != null ? "有" : "无"}\n'
      '刷新凭证：${refreshToken != null ? "有" : "无"}\n'
      '必要 Cookie：${['SESSDATA', 'bili_jct', 'DedeUserID'].map((name) => '$name=${cookies.any((c) => c['name'] == name && c['value']!.isNotEmpty) ? "有" : "无"}').join('，')}';

  static String? _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static String safeMessage(Object? value) {
    if (value is! String) return '无消息';
    // Suppress any message containing credential labels rather than trying to
    // guess where an echoed cookie/token ends. Ordinary server errors survive.
    if (RegExp(
      r'access[_-]?(token|key)|refresh[_-]?token|SESSDATA|bili_jct|auth_code|qrcode_key|cookie|authorization',
      caseSensitive: false,
    ).hasMatch(value)) {
      return '服务器消息包含登录资料，已隐藏';
    }
    final text = value
        .replaceAll(RegExp(r'https?://\S+'), '[链接已隐藏]')
        .replaceAll(RegExp(r'[A-Za-z0-9_%+/=-]{24,}'), '[内容已隐藏]')
        .replaceAll(RegExp(r'[\r\n\t]'), ' ');
    return text.length <= 180 ? text : '${text.substring(0, 180)}…';
  }
}

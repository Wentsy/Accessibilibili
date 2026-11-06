/// Old clients receive this placeholder even when picture data is available.
String replyDisplayText(String message, {required bool hasPictures}) {
  if (!hasPictures) return message;
  return message
      .replaceAll('[请升级到App最新版本查看图文评论]', '')
      .replaceAll('[請升級到App最新版本查看圖文評論]', '')
      .trim();
}

# 2.1.7+6033: feed regression and automatic Passport refresh

## Feed regression
The broad REST identity rewrite in 6032 changed Android live-feed endpoints into iphone_i requests. Restore the existing endpoint-specific REST identity except for Passport requests and app.bilibili.com requests. Do not substitute the Web feed. Keep international gRPC identity (including working IM) and the avatar-to-conversation fix.

Normalize Cookie headers from String or Iterable before merging. Dio request reuse can contain list-valued headers; the former String cast would throw locally. This is a source-level fix for the reported type error, not a completed live reproduction.

Error notifications/debug messages no longer append query strings or arbitrary Dio exception bodies. Refresh calls suppress error toasts and transport retries.

## Native evidence
Inspected the supplied unencrypted com.bilibili.inter 3.13.0 binary with LLVM AArch64 disassembly and Objective-C method/selector resolution:
- requestRefreshTokenWithRefreshToken:accessKey:sts:completionBlock: at 0x10bdf3210 POSTs refresh_token, access_key, sts and device identifiers to x/passport-login/oauth2/refresh_token.
- requestTimestampWithCompletionBlock: at 0x10bdf3da8 GETs x/passport-login/timestamp.
- refreshTokenWithCompletionBlock: at 0x10bdf7e44 requests server time; its callbacks use the prior SSO model, install the new SSO model at 0x10bdf853c and call confirmRefreshWithSSOModel:sts: with the OLD model at 0x10bdf8550.
- confirmRefreshWithSSOModel:sts: at 0x10bdfb458 extracts DedeUserID and SESSDATA from the old model, and passes old access/refresh tokens, session, sts and REFRESH_CONFIRM_REVOKE.
- requestConfirmRefreshWithMid:accessToken:refreshToken:session:revokeApi:sts:completionBlock: at 0x10bdf3a2c POSTs those fields to x/passport-login/confirm/refresh.

## Implemented
Automatic pre-dispatch refresh for accounts marked internationalPassport with both tokens. Check oauth2/info at first use and at most hourly; refresh when the server requests it, expiry is near, or info returns -101. Use timestamp -> refresh -> validate matching mid and complete cookies/tokens -> persist -> confirm old credentials. Invalid replies do not replace the session.

Concurrent requests for an account await one refresh. Failures cool down for ten minutes. Pending confirmations survive Hive/JSON backup and are retried before another rotation. Deleted/replaced accounts cannot be restored by late responses. Old credential parameters in waiting requests are updated/re-signed. Business operations are not replayed after a server response. The refresh transport has no automatic retries or redirects. Main-account WebView cookie synchronization is best effort.

Legacy/anonymous/Cookie-only accounts do not use this international refresh protocol.

## Validation
Added regression tests for Cookie list normalization, refresh concurrency, wrong-account responses, logout races, failed confirmation persistence/retry and failure cooldown.
No Flutter/Dart SDK is installed locally; tests and compilation must run in the supplied tests-only CI or locally. No live account refresh was performed. Server acceptance and feed functionality still require device verification.

Run:
flutter test test/utils/http_auth_values_test.dart test/utils/passport_refresh_test.dart test/utils/accounts/international_passport_test.dart test/utils/accounts/deleted_account_test.dart test/models/qr_login_test.dart

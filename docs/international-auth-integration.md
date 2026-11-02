# Authentication integration — 2.1.7+6032

Includes the user-verified Passport/IM login work and private-message avatar navigation fix from 2.1.7+6031.

## Changes

- All gRPC metadata now follows the saved account origin, not just the IM namespaces. Legacy accounts retain Android HD.
- Signed REST requests use international general API keys for API hosts, and Passport keys for passport.bilibili.com. Unsigned web Cookie/CSRF requests remain web requests.
- Replace conflicting signed client parameters and case-insensitive User-Agent / app-key headers. Remove Android numeric statistics rather than invent international IDs.
- Signing removes any old signature before computing a new one, including repeat signing by the interceptor.
- Login-device queries use the selected account BUVID and bind the request to that account.
- Remove the failed web Cookie-to-App authorization action and its UI. Existing standalone Cookie login, password, SMS and legacy QR are retained.
- The earlier avatar-to-conversation fix is included unchanged.

## Evidence and limits

The supplied com.bilibili.inter 3.13.0 binary contains the general key / secret pair 27eb53fc9058f8c3 / c2ed53a74eeefe3cf99fbd01d8c9c375 and the separate Passport pair. This builds on the previous native request-builder investigation. Static fallback constants do not prove every live API's accepted identity.

IM was reported working by the user before this integration. Other gRPC services, signed live endpoints, TV play URLs and login-device queries require device testing. A service may still impose client-specific limitations; a coherent identity does not guarantee support.

Automatic token refresh is NOT implemented. The native binary contains x/passport-login/oauth2/refresh_token, requestRefreshTokenWithRefreshToken:accessKey:sts:completionBlock: and requestConfirmRefreshWithMid:accessToken:refreshToken:session:revokeApi:sts:completionBlock:. Their parameter and confirmation contract has not been established. Do not guess it or silently replace working credentials. Refresh tokens continue to be stored.

## Validation

Reviewed the changed routing/signing paths and added signature, header casing and metadata-origin regression coverage. No Flutter/Dart SDK is available in the editing environment: these tests and compilation have NOT run.

Local commands:
- flutter test test/utils/client_identity_test.dart test/utils/accounts/international_passport_test.dart test/models/qr_login_test.dart
- flutter analyze lib/utils/client_identity.dart lib/utils/app_sign.dart lib/utils/accounts lib/http/login.dart lib/pages/login

Device checks: private-message row/avatar activation with touch and VoiceOver; send/receive messages; comments/danmaku/dynamics/audio; live lists/search; playback; login devices; switching between legacy and international accounts; restart and backup import.

No IPA build requested. Keep local build scripts from overriding 2.1.7+6032 unintentionally.

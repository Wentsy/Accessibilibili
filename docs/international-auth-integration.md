# Authentication integration — 2.1.7+6047 / source 2.1.7+6033

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

Automatic Passport token refresh is implemented for accounts marked `internationalPassport`. It checks `oauth2/info` at first use and at most hourly, refreshes when needed, validates the returned account identity and cookies/tokens, persists the new credentials, and confirms the old credentials. Failed refreshes do not replace the current session and are subject to a cooldown. Legacy, anonymous and Cookie-only accounts do not use this protocol.

## Validation

Reviewed the changed routing/signing paths and added signature, header casing and metadata-origin regression coverage. No Flutter/Dart SDK is available in the editing environment: these tests and compilation have NOT run.

Local commands:
- flutter test test/utils/client_identity_test.dart test/utils/accounts/international_passport_test.dart test/models/qr_login_test.dart
- flutter analyze lib/utils/client_identity.dart lib/utils/app_sign.dart lib/utils/accounts lib/http/login.dart lib/pages/login

Device checks: private-message row/avatar activation with touch and VoiceOver; send/receive messages; comments/danmaku/dynamics/audio; live lists/search; playback; login devices; switching between legacy and international accounts; restart and backup import.

The verified CI IPA is `2.1.7+6047`, built from source commit `9a1b241b`. Keep local build scripts from overriding the source version or confusing the CI build number when comparing future upstream syncs.

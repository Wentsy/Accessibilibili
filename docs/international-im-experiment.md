# International Passport IM experiment — 2.1.7+6030

Based on international-passport-qr commit 87f84befd8ca8c396bfda916ea6cd3b34b541f10.

User testing confirms Passport QR login and likes work. Both the international account and a mainland account fail private-message authentication after this QR login. Restoring the mainland account's previous login backup restores messaging. This isolates a credential/client-path difference, but does not prove its server-side cause.

Code inspection confirms all gRPC requests previously advertised Android HD, regardless of token origin. Persist the Passport origin in Hive field 5 and JSON backups; old records default to legacy. Use the international metadata experiment only for the two IM service namespaces. Preserve the login BUVID. No Cookie-login substitution or automatic resend is introduced.

The iOS metadata uses the observed iphone_i / ios / phone / 68500200 profile. appstore, Apple and iPhone are experimental device descriptors; the numeric international app ID is not established, so it is omitted, not guessed. This is not a captured official IM request and may still be rejected or unsupported by the service.

## Local verification
The editing environment has no Flutter or Dart SDK. Flutter compilation, analyzer, and the included regression test have NOT run. No live messaging test has run.

Run:
`flutter test test/utils/accounts/international_passport_test.dart`
`flutter analyze lib/utils/accounts lib/pages/login/controller.dart`

Then build locally as 2.1.7+6030 (ensure local build scripts do not overwrite that number).

## Device acceptance
Existing records from the previous experiment have no origin marker. Log in once again using International Passport QR on this build; do not infer origin from the global QR toggle. Confirm conversation history, one manually sent message, and received messages. Restart and repeat. Check legacy login backups still use legacy metadata. A successful request is required before calling this a fix.

No IPA build workflow was requested. Branch: experiment/international-passport-im.

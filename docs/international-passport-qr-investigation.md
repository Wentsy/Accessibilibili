# International Passport QR investigation

## Reproduction

International iOS 6.7.0 (91600300) and the supplied 3.13.0 IPA can sign into the account. Scanning Accessibilibili and confirming returns 48007 with no access token, refresh token, or required cookies. Both earlier QR modes used the same Android HD signing identity.

## Static evidence

The supplied IPA identifies as com.bilibili.inter 3.13.0 (68500200). The main Mach-O reports cryptid 0. This is a supplied repackaged IPA, not an independently authenticated App Store binary.

Addresses below are unslid virtual addresses in that binary:

- BFCBuildConfig.mobiApp (0x10bf09c3c): fallback iphone_i.
- BFCBuildConfig.appKey (0x10bf09d34): general API fallback 27eb53fc9058f8c3.
- BFCBuildConfig.passportKey (0x10bf09f24): separate Passport fallback 5ae412b53418aac5. The matching secret is in passportSecret at 0x10bf0a01c.
- BFCAccountApi._request:params:method:completionBlock: (0x10bdf16a4): adds sdk_ver 0.1.15 and sets apiKeySecretType to 1.
- BFCAccountGolangApi.requestQRCodeWithGourl:completionBlock: (0x10bdf51fc): uses x/passport-tv-login/qrcode/auth_code.
- requestQRCodePollWithAuthCode:deviceFields:completionBlock: (0x10bdf5458): uses x/passport-tv-login/qrcode/poll.
- Both QR methods set local_id from buvid and add bili_local_id, device_id, buvid, device_name and device_platform. The native code gets these from different device providers; this experiment uses one stable anonymous BUVID for the identifier fields.
- BFCApiSignHelper.baseParams (0x10be49834) adds ios, device, build, mobi_app, appkey, actionKey and other common parameters.

The getters permit runtime overrides. Static fallback values do not prove the identity used by every live request. Presence of these methods does not prove which UI calls them.

## Implemented experiment

A separate branch uses the observed Passport signing pair for QR generation and polling, with iphone_i/iOS parameters and stable device identifiers. It sends form bodies and uses NoAccount to prevent the account interceptor from attaching unrelated cookies or headers. The legacy QR path remains available.

This is a targeted experiment, not a complete reproduction of the native request. For example, native locale/statistics/feature parameters and runtime overrides have not been captured. General REST and gRPC signing are unchanged. A successful token response therefore does not establish full feature compatibility.

## Acceptance

1. Build the branch IPA successfully.
2. Select International Passport QR and scan with the same account.
3. Confirm on the official client.
4. Require code 0 and valid account-matched credentials; never treat 48007 as success.
5. Verify access token, refresh token and required cookies are present without copying their values.
6. Verify the originally missing App-backed functions and token refresh separately.

If 48007 persists, the experiment has not resolved authorization. Do not repeat the same configuration or substitute Cookie login. Investigate the server's allowed account/client combinations using a redacted request trace or supported platform documentation.

No live account authorization or feature test was performed in the analysis environment.

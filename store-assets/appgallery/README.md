# AppGallery listing assets

## Pricing

**This app is free.** The listing must be submitted as a free app: the app contains no in-app purchase, no subscription and no paywall, so there is nothing to sell at listing time beyond marking it free.

Two related notes, so the listing copy does not contradict the build:

- The `module.json5` field `installationFree` must stay `false`. It means "supports free-installation / atomic-service packaging", **not** "the app is free to install" — setting it to `true` would treat the module as an atomic service and route it through a separate signing and review track.
- The only external cost a user can incur is the AI food-recognition API, which is billed by the user's own model provider against their own API key. Do not imply the app itself charges anything, and do not imply the app supplies the API either.

## App icon

- `icon-1024.png` is a 1024 × 1024 RGB PNG rendered from the app's vector launcher icon at `entry/src/main/resources/base/media/caloriefit_start_icon.svg`.
- AppGallery's current phone/tablet asset table accepts a square icon at 216 × 216 or 1024 × 1024, as PNG up to 3 MB. Source: [Asset Specifications](https://developer.huawei.com/consumer/en/doc/agc-help-app-visual-asset-spec-0000002277607976).

## Screenshots

The listing screenshot set is not prepared yet. Capture 3–5 portrait screenshots at 1080 × 1920 from the final, device-verified build. Existing regression screenshots belong to older HAPs and must not be presented as screenshots of the current build.

Before capture, confirm the actual release UI, clear personal data, and ensure any demo values are visibly identified as examples. Do not include API keys, account details, or real health records.

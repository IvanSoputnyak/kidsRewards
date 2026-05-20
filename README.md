# KidsRewards

A **free** local SwiftUI iOS app for family reward points—chores, available/vault balances, allowance, parent PIN, child requests, and JSON backup. No server, no subscriptions, no in-app purchases, no real payments.

## Free for you and your family

| Cost | Amount |
|------|--------|
| App for users | **$0** — no IAP, ads, or subscriptions |
| Apple Developer Program | **$0** — install from Xcode with a personal Apple ID |
| Cloud backup in default build | **$0** — export/import JSON (no iCloud required) |

Details: **[Docs/FreeDistribution.md](Docs/FreeDistribution.md)**

## Run in Xcode

1. Open `KidsRewards.xcodeproj`.
2. Select the **KidsRewards** target → **Signing & Capabilities** → your **Personal Team**.
3. Run on a simulator or your device (⌘R).

Free provisioning profiles renew about every **7 days** — run from Xcode again to refresh.

## Back up data

**Settings → Export JSON** → AirDrop or Files → on another device, **Import JSON**.

iCloud sync is **disabled** in the default build (`KidsRewards/Stores/AppDistribution.swift`). Enable only if you join the paid Apple Developer Program — see [Docs/iCloudEntitlement.md](Docs/iCloudEntitlement.md).

## Documentation

| Doc | Purpose |
|-----|---------|
| [Docs/FreeDistribution.md](Docs/FreeDistribution.md) | **$0 install and backup** (start here) |
| [Docs/PreRelease.md](Docs/PreRelease.md) | Out of scope, UI placement, release verdict |
| [Docs/FunctionalityAnalysis.md](Docs/FunctionalityAnalysis.md) | Implemented features + architecture |
| [Docs/iCloudEntitlement.md](Docs/iCloudEntitlement.md) | Optional iCloud (paid Apple program only) |
| [Docs/BiometricValidation.md](Docs/BiometricValidation.md) | Face ID / Touch ID device checklist |

## Tests

From Xcode: **Product → Test**, or:

```bash
xcodebuild test -scheme KidsRewards -sdk iphonesimulator -destination 'generic/platform=iOS Simulator'
```

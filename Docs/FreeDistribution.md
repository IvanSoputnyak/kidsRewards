# Free distribution (no cost on your side)

KidsRewards is built to ship **without paying Apple** or running paid cloud services.

| Doc | Role |
|-----|------|
| This file | How to install and back up for $0 |
| [PreRelease.md](./PreRelease.md) | Out of scope, UI placement, release verdict |
| [FunctionalityAnalysis.md](./FunctionalityAnalysis.md) | Implemented features + architecture |
| [iCloudEntitlement.md](./iCloudEntitlement.md) | Optional — only if you later pay Apple $99/year |

**Build flag:** `KidsRewards/Stores/AppDistribution.swift` — `iCloudKeyValueBackupEnabled` is `false` in the default (free) configuration.

## What costs money (and what we skip)

| Option | Apple fee | This project |
|--------|-----------|--------------|
| **Personal team** (free Apple ID in Xcode) | $0 | **Default** — install on your own devices |
| **Apple Developer Program** | $99/year | Not required for family use |
| **App Store listing** | Requires paid program | Not the target for now |
| **iCloud key-value backup** | Requires paid program + entitlement | **Off** in app (`AppDistribution.iCloudKeyValueBackupEnabled = false`) |
| **In-app purchases / subscriptions** | — | None — app is free for users |

## How to install for your family (free)

1. Open `KidsRewards.xcodeproj` in Xcode.
2. Select the **KidsRewards** target → **Signing & Capabilities**.
3. Choose your **Personal Team** (your Apple ID). Xcode creates a free provisioning profile.
4. Connect an iPhone or iPad (or use Simulator for trying the UI).
5. **Product → Run** (⌘R).

Repeat on each family device, or share the project so another parent builds with their own Apple ID.

**Note:** Free provisioning profiles expire after about **7 days**; run from Xcode again to refresh, or enroll in the paid program for longer-lived profiles and TestFlight.

## How families back up data (free)

- Data lives in the app’s local JSON file automatically.
- **Settings → Export JSON** → save to **Files**, **AirDrop**, or email.
- On another device: **Import JSON** (replaces local data).

No iCloud account required for backup.

## App is free for users

- No subscriptions, no ads, no in-app purchases in this codebase.
- Points and “cash out” are a **household ledger only** — parents pay kids outside the app.

## If you later pay for Apple Developer ($99/year)

You can optionally:

1. Enroll at [developer.apple.com](https://developer.apple.com/programs/).
2. Set a real bundle ID (replace `com.example.KidsRewards`).
3. Enable iCloud per [iCloudEntitlement.md](./iCloudEntitlement.md).
4. Set `AppDistribution.iCloudKeyValueBackupEnabled = true` in `KidsRewards/Stores/AppDistribution.swift`.
5. Distribute via TestFlight or App Store.

Until then, keep the free flags as shipped.

## What families should know

- The app does **not** move real money — cash out is a household ledger; parents pay kids outside the app.
- There are **no ads**, **no subscriptions**, and **no in-app purchases**.
- Moving to a new phone: export JSON on the old device, import on the new one.

## Related

- [PreRelease.md](./PreRelease.md) — feature scope
- [iCloudEntitlement.md](./iCloudEntitlement.md) — paid-team iCloud only
- [../README.md](../README.md) — quick start

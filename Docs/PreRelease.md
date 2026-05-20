# KidsRewards — Pre-Release Review

**Purpose:** Lock scope before release — what is **out of scope**, what is **misplaced in the UI**, and whether the app is ready for free family install.

**Distribution:** [FreeDistribution.md](./FreeDistribution.md) — free for users, **$0 Apple fee**, JSON backup, iCloud UI off via `AppDistribution`.

**Implemented feature list:** [FunctionalityAnalysis.md](./FunctionalityAnalysis.md) § Implemented features.

---

## 1. Summary

The app is **ready for private family use** via Xcode and a personal Apple ID: full points/chores/vault/allowance flows, child mode, approvals, PIN safety, and JSON backup.

**Strongest:** `RewardStore` + ~100 unit tests.  
**Weakest:** Information architecture and thin UI test coverage.

| Focus | Notes |
|-------|--------|
| Ship now | Core family flows + JSON backup |
| Out of scope | Payments, accounts, reports, auto cloud sync (free build) |
| Fix or accept | UI placement and polish (§3–§4) |

---

## 2. Out of scope (not bugs)

- Real payment processing; App Store without paid Apple Developer Program ($99/year).
- User accounts, sign-in, automatic multi-device sync (use **Export/Import JSON**).
- Reports, charts, CSV/PDF, transaction filters, onboarding wizard, localization, dark mode.
- Merge/partial import; kid-initiated manual adjust; soft-delete/archive kids.
- In-app purchases, ads, subscriptions.

**Intentional product choices (documented in UI, not missing features):** cash out is a ledger entry only; allowance/interest schedules run when the app opens.

---

## 3. Misplaced in the UI (exists, hard to find)

| Issue | Today | Expected by parents |
|-------|--------|---------------------|
| Allowance amount & schedule | Per-kid **Available** + home quick action | **Settings** with other economy rules |
| Approval queue | Deep in **Settings** | Near approval toggle; badge on Settings tab |
| Award chore | **Kid detail** only | Work tab doesn’t award; home “chores ready” doesn’t navigate |
| Interest / chores attention rows | Home cards, **no tap action** | Navigate to vault/kid or look non-tappable |
| Allowance config vs “Apply now” | Mixed on **Available** | Separate config from action |
| Transaction fix | Kid history only | Not from home recent activity |
| Kid nav title | Back title **“Kids”** | Kid’s name |
| Vault withdraw | **Vault** screen | Easy to miss if only using Available |

### Navigation depth (acceptable, not missing)

| Goal | Path |
|------|------|
| Cash out | Kids → kid → Available |
| Award chore | Kids → kid → chore |
| Approve request | Home → Approvals → Settings queue |
| Allowance schedule | Kids → kid → Available |

---

## 4. Open polish (optional before v1.0)

- Wire or de-emphasize home **interest due** / **chores ready** rows.
- Kid name in navigation title on kid detail.
- Settings tab badge for pending approvals (optional).
- Consistent app name in strings (“Kids Rewards” vs “KidCoin Keeper”).
- Expanded UI tests (optional).

---

## 5. Qualified behavior (know when shipping)

| Topic | Note |
|-------|------|
| JSON backup | Primary path for free builds |
| iCloud | Off unless paid program + `AppDistribution` + [iCloudEntitlement.md](./iCloudEntitlement.md) |
| Schedules | Allowance/interest when app opens; not if app never opened |
| Notifications | Need user permission |
| Approvals | One pending per kid per kind |
| Savings goal | Progress = available + vault |
| Weekly rules | Calendar week (Sunday), not rolling 7 days |

---

## 6. Verdict

### Ready for

- Install from Xcode on family devices (personal Apple ID).
- Daily single-device use with occasional JSON export.
- Shared iPad child mode with approval flow on.

### Not ready for

- App Store without paid program, bundle ID, and store assets.
- Households expecting auto-sync without JSON export/import.
- Allowance on a schedule if the app is never opened.

### Defer post–v1.0

Onboarding, reports, localization, dark mode, moving allowance defaults to Settings, iCloud for paid teams only.

---

## 7. Related documents

| Doc | Use |
|-----|------|
| [FreeDistribution.md](./FreeDistribution.md) | $0 install and backup |
| [FunctionalityAnalysis.md](./FunctionalityAnalysis.md) | Implemented features + architecture |
| [iCloudEntitlement.md](./iCloudEntitlement.md) | Optional paid-program iCloud |
| [BiometricValidation.md](./BiometricValidation.md) | Device checklist |
| [../README.md](../README.md) | Quick start |
| `KidsRewards/Stores/AppDistribution.swift` | `iCloudKeyValueBackupEnabled` |

---

*Update when behavior changes. Do not re-list implemented features here — use FunctionalityAnalysis.md.*

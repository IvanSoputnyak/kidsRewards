# iCloud key-value backup (optional, paid Apple program only)

**Default builds are free:** `AppDistribution.iCloudKeyValueBackupEnabled` is `false`, iCloud UI is hidden, and JSON export/import is the backup path. See [FreeDistribution.md](./FreeDistribution.md).

Personal Apple Developer teams **cannot** enable the iCloud capability. The Xcode target has **no entitlements file** linked, so free/personal teams can sign the app.

Local JSON save, export/import, and all other features work without iCloud.

## Enable iCloud (paid Apple Developer Program only)

0. In `KidsRewards/Stores/AppDistribution.swift`, set `iCloudKeyValueBackupEnabled = true`.

1. Open the **KidsRewards** target in Xcode → **Signing & Capabilities**.
2. Click **+ Capability** → **iCloud** → enable **Key-value storage**.
3. Create `KidsRewards/KidsRewards.entitlements` (see `Docs/KidsRewards.iCloud.entitlements.example`), set **Code Signing Entitlements** on the target to that file, and add:

```xml
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)YOUR_BUNDLE_ID</string>
```

Use the same bundle ID as `PRODUCT_BUNDLE_IDENTIFIER` (replace `com.example.KidsRewards` with your own ID in the target’s **General** tab).

4. Clean build folder and build again on a device signed into iCloud.

Settings → **Reminders & Sync** will show **Auto-sync to iCloud**, and **Data** will show **Sync to iCloud** / **Restore iCloud**, once the capability is active and the user is signed into iCloud on the device.

Until steps 0–4 are done, keep `iCloudKeyValueBackupEnabled = false` so the free build UI stays on JSON backup only.

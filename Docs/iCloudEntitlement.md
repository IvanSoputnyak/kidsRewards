# iCloud key-value backup (optional)

Personal Apple Developer teams **cannot** enable the iCloud capability. The Xcode target has **no entitlements file** linked, so free/personal teams can sign the app.

Local JSON save, export/import, and all other features work without iCloud.

## Enable iCloud (paid Apple Developer Program only)

1. Open the **KidsRewards** target in Xcode → **Signing & Capabilities**.
2. Click **+ Capability** → **iCloud** → enable **Key-value storage**.
3. Create `KidsRewards/KidsRewards.entitlements` (see `Docs/KidsRewards.iCloud.entitlements.example`), set **Code Signing Entitlements** on the target to that file, and add:

```xml
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)YOUR_BUNDLE_ID</string>
```

Use the same bundle ID as `PRODUCT_BUNDLE_IDENTIFIER` (replace `com.example.KidsRewards` with your own ID in the target’s **General** tab).

4. Clean build folder and build again on a device signed into iCloud.

Settings → **Auto-sync to iCloud** / **Sync to iCloud** will work once the capability is active and the user is signed into iCloud on the device.

# Real Device Biometric Validation

Use this checklist on a physical iPhone or iPad because Simulator cannot prove Face ID or Touch ID enrollment behavior.

## Setup

- Install a debug build on a device with Face ID or Touch ID enrolled.
- Open Settings in Kids Rewards and set a parent PIN.
- Force quit and reopen the app.

## Expected Behavior

- Parent controls are blocked by the Parent PIN gate after relaunch.
- "Use Face ID / Touch ID" appears only on devices where biometrics are available.
- A successful biometric match unlocks parent controls.
- A failed biometric match keeps the gate visible and shows "Biometric unlock failed."
- Tapping Child Mode still enters child mode without exposing parent controls.
- Removing the parent PIN removes the lock gate on the next launch.

## Negative Cases

- Disable Face ID / Touch ID enrollment in iOS Settings and relaunch. The biometric button should not appear.
- Cancel the system biometric prompt. Parent controls should stay locked.
- Restart the device and relaunch. The app should still require parent PIN or successful biometric unlock.

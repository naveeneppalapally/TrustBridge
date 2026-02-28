# TrustBridge Maximum Protection (One-Time Setup)

Use this only on the **child phone** if you want the strongest tamper resistance.

## What this does

- Makes TrustBridge the device owner on the child phone.
- Enables always-on protection lock mode.
- Helps block force-stop and uninstall bypass attempts.

## What you need

- A laptop (Windows/macOS/Linux)
- USB cable
- Child phone with TrustBridge already installed
- ADB installed on the laptop

## Steps

1. Connect the child phone to your laptop with USB.
2. On the child phone, enable Developer Options and USB debugging.
3. On your laptop, open Terminal/PowerShell in any folder.
4. Run:

```bash
adb devices
adb shell dpm set-device-owner com.navee.trustbridge/.TrustBridgeAdminReceiver
```

5. Open TrustBridge on the child phone.
6. Go to **Settings -> Maximum Protection** and tap **Apply Now**.

## Verify it worked

- In TrustBridge -> **Settings -> Maximum Protection**:
  - Device Owner: Active
  - Always-on protection: Active
  - Lockdown mode: Active
  - Uninstall blocked: Active

## If the command fails

- If you see a message saying the device is already provisioned, Android is not allowing device-owner assignment on the current setup.
- In that case, run this during fresh device provisioning (typically after a factory reset) and then repeat the command.

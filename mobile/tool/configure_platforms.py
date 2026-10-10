"""Add the permissions/settings this app needs to the native projects that
`flutter create` generates. Safe to run repeatedly (idempotent).

Usage, from mobile/:
    flutter create . --project-name glasses_tryon --org com.example --platforms android,ios
    python tool/configure_platforms.py

Android
  * CAMERA, INTERNET permissions; WRITE_EXTERNAL_STORAGE only for API <= 29
    (saving to the gallery on old Android, required by the `gal` plugin)
  * requestLegacyExternalStorage (gal, API 29)
  * cleartext HTTP allowed in debug/profile builds only, so the app can reach
    a local FastAPI server over http://<LAN-IP>:8000 during development
  * minSdk >= 24 (camera plugin requirement)
iOS
  * camera / microphone / photo library usage descriptions
  * local-network HTTP allowed (NSAllowsLocalNetworking) for development
  * deployment target 15.5 (Google ML Kit requirement)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS_MIN = "15.5"
APP_NAME = "Frame Finder"

ANDROID_PERMISSIONS = [
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.CAMERA" />',
    '<uses-feature android:name="android.hardware.camera" android:required="false" />',
    # The camera plugin also declares this (maxSdkVersion 28); tools:replace
    # makes the manifest merger keep our value, which gal needs on API 29.
    '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" tools:replace="android:maxSdkVersion" />',
]

IOS_KEYS = {
    "NSCameraUsageDescription": "The camera is used to preview eyeglasses on your face. Video is processed on your device and never uploaded.",
    "NSMicrophoneUsageDescription": "The microphone is not used. This description is required by the camera plugin.",
    "NSPhotoLibraryUsageDescription": "Choose a photo to try glasses on, and save your try-on pictures.",
    "NSPhotoLibraryAddUsageDescription": "Save your try-on pictures to Photos.",
    "NSLocalNetworkUsageDescription": "Connect to the eyeglass catalogue server on your local network during development.",
}

changes: list[str] = []


def _write(path: Path, old: str, new: str) -> None:
    if new != old:
        path.write_text(new, encoding="utf-8")
        changes.append(str(path.relative_to(ROOT)))


def patch_android_manifest(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    new = text
    missing = [p for p in ANDROID_PERMISSIONS if re.search(r'android:name="([^"]+)"', p).group(1) not in new]
    # Upgrade a WRITE_EXTERNAL_STORAGE line written by an older version of this script.
    new = new.replace(
        '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />',
        ANDROID_PERMISSIONS[3],
    )
    if missing:
        block = "".join(f"    {p}\n" for p in missing)
        new = re.sub(r"(\n\s*<application)", "\n" + block.rstrip("\n") + r"\1", new, count=1)
    if "tools:replace" in new and "xmlns:tools" not in new:
        new = new.replace(
            'xmlns:android="http://schemas.android.com/apk/res/android"',
            'xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    xmlns:tools="http://schemas.android.com/tools"',
            1,
        )
    new = re.sub(r'(<application[^>]*?android:label=")[^"]*(")', rf"\g<1>{APP_NAME}\g<2>", new, count=1, flags=re.S)
    if "requestLegacyExternalStorage" not in new:
        new = re.sub(r"<application\b", '<application\n        android:requestLegacyExternalStorage="true"', new, count=1)
    _write(path, text, new)


def patch_android_dev_manifest(path: Path) -> None:
    """debug/profile manifests: allow http:// to a LAN dev server."""
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if "usesCleartextTraffic" in text:
        return
    new = text.replace(
        "</manifest>",
        '    <application android:usesCleartextTraffic="true" />\n</manifest>',
        1,
    )
    _write(path, text, new)


def patch_android_gradle(app_dir: Path) -> None:
    for name in ("build.gradle.kts", "build.gradle"):
        path = app_dir / name
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        kts = name.endswith(".kts")
        new = re.sub(
            r"minSdk(?:Version)?\s*=?\s*flutter\.minSdkVersion",
            "minSdk = maxOf(flutter.minSdkVersion, 24)" if kts else "minSdk = Math.max(flutter.minSdkVersion, 24)",
            text,
        )
        _write(path, text, new)
        return
    print("! android/app/build.gradle(.kts) not found: set minSdk to 24 or higher manually")


def patch_info_plist(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    additions = ""
    new_text = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", rf"\g<1>{APP_NAME}\g<2>", text)
    if new_text != text:
        _write(path, text, new_text)
        text = new_text
    for key, value in IOS_KEYS.items():
        if f"<key>{key}</key>" not in text:
            additions += f"\t<key>{key}</key>\n\t<string>{value}</string>\n"
    if "<key>NSAppTransportSecurity</key>" not in text:
        additions += (
            "\t<key>NSAppTransportSecurity</key>\n\t<dict>\n"
            "\t\t<key>NSAllowsLocalNetworking</key>\n\t\t<true/>\n\t</dict>\n"
        )
    if not additions:
        return
    idx = text.rfind("</dict>")
    new = text[:idx] + additions + text[idx:]
    _write(path, text, new)


def patch_ios_deployment_target(ios_dir: Path) -> None:
    pbx = ios_dir / "Runner.xcodeproj" / "project.pbxproj"
    if pbx.exists():
        text = pbx.read_text(encoding="utf-8")
        new = re.sub(
            r"IPHONEOS_DEPLOYMENT_TARGET = (\d+(?:\.\d+)?);",
            lambda m: m.group(0) if float(m.group(1)) >= float(IOS_MIN) else f"IPHONEOS_DEPLOYMENT_TARGET = {IOS_MIN};",
            text,
        )
        _write(pbx, text, new)
    podfile = ios_dir / "Podfile"
    if podfile.exists():
        text = podfile.read_text(encoding="utf-8")
        new = re.sub(r"^#?\s*platform :ios, '[\d.]+'", f"platform :ios, '{IOS_MIN}'", text, count=1, flags=re.M)
        if "platform :ios" not in new:
            new = f"platform :ios, '{IOS_MIN}'\n" + new
        _write(podfile, text, new)
    else:
        print(f"i ios/Podfile not generated yet. After your first iOS build, run this script again "
              f"(or set `platform :ios, '{IOS_MIN}'` in ios/Podfile).")


def main() -> int:
    android = ROOT / "android"
    ios = ROOT / "ios"
    if not android.exists() and not ios.exists():
        print("No android/ or ios/ folder. Run first:\n"
              "  flutter create . --project-name glasses_tryon --org com.example --platforms android,ios")
        return 1
    if android.exists():
        patch_android_manifest(android / "app/src/main/AndroidManifest.xml")
        patch_android_dev_manifest(android / "app/src/debug/AndroidManifest.xml")
        patch_android_dev_manifest(android / "app/src/profile/AndroidManifest.xml")
        patch_android_gradle(android / "app")
    if ios.exists():
        patch_info_plist(ios / "Runner/Info.plist")
        patch_ios_deployment_target(ios)
    print("Updated:\n  " + "\n  ".join(changes) if changes else "Already configured; nothing to change.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

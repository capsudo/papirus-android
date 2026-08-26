# Papirus Icon Pack
Popular Linux icon theme now on Android!

<p align="center">
  <img src="https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus_icons/master/preview.png" alt="preview"/>
</p>

## Supported Launchers:
Below launchers have been tested to be working successfully with Papirus Icon among others. Feel free to add yours:

- Flick
- Holo
- Lawnchair
- Lucid
- Nova
- Posidon
- Smart
- HiOS
- _and many others..._

## Features:
- Fully Open Source
- Pixel perfect
- More than 5000 icons
- Inspired by Material design
- Icon Request option
- Check Update function
- 8 Cloud Wallpapers

## Install
1. Download the apk from [latest release](../../releases/latest)
2. Install it (allow sources if needed)
3. Click "Apply icon pack" from the app (for supported launchers)

# Fork

This is a fork of [Papirus Android icon pack repo](https://github.com/PapirusDevelopmentTeam/papirus_icons/tree/master/scripts) which is outdated and not kept up to date with upstream [Papirus icon theme repo](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme).
At time or writing last release [available on opendesktop.org](https://www.opendesktop.org/p/1662847/) is 20220220.

This fork adds an update script that pulls icons from the upstream repo.

## Sync current Papirus icons

Run `scripts/update_icons.sh` to update icons in `src/` from [Papirus icon theme repo](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme).

```bash
scripts/update_icons.sh --dry-run
scripts/update_icons.sh
```

Notes:
- Icons are sourced from `Papirus/64x64/apps`.
- The icon names are converted to Android resource names: it adds `apps_`, changes uppercase letters to lowercase and changes punctuation to `_`. eg. `firefox-focus.svg` => `apps_firefox_focus.svg`.
- Existing icons that are not present in the update are not deleted.
- A (shallow) checkout of papirus-icon-theme is storead in `.cache/`, so [papirus-icon-theme repo](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) is only cloned once on the first run, next runs only downloads new icon changes.
- VSC (VS Code & Codium) task available.

## Icon mappings

[data.json](/data.json) maps each icon resource name to Android `package/activity` components. `make build` generates `appfilter.xml` from these mappings.

To be correctly mapped to an android app (and applied automatically to an installed app by launcher) the correct application id and launcher activity name is required. A dummy activity name (`ReplaceWithRealActivityLauncher`) was used when the real launcher activity is not known.

Most of the icons from [Papirus icon theme repo](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) are not android apps, yet they are all included and mapped in this pack so they can still be used for as custom icons (for instance to set a custom icon for a PWA app added on home screen). For those a dummy application id `io.github.papirusdevelopmentteam.papirus_icons.placeholder.ICON_NAME` and a dummy activity name `FakeActivityLauncher` are used.

If an icon is not correctly mapped to an app, search for it in the [mapping](/data.json) and [open an issue](/issues/new) or [make a PR](/compare) if it needs to be updated. 

## Build debug APK

make build after changing icons or data.json; then run Gradle to create the APK.

1. Build icon resources
   ```bash
    make build
   ```
   - checks data.json and SVG icon filenames
   - converts the SVG files in src/ into PNG files in app/src/main/res/drawable-nodpi/
   - generates appfilter.xml, which maps Android app activities from data.json to icon names
   - generates drawable.xml, the list of icons shown by the icon-pack app

2. Assemble debug APK
   ```bash
   ./gradlew assembleDebug
   ```

   takes those generated PNG/XML resources plus the Android app code and compiles them into a debug APK, written in `app/build/outputs/apk/debug/`.

Notes:
- VSC tasks available.
- Nix shell is provided with dependencies: Java 11, Android API 31, Android build tools and the icon conversion tools. VSC shell tasks should load this shell with direnv automatically. Run `direnv allow` once after cloning this project or changing `.envrc`.

## Build release APK

Build icon resources first if icons or data.json changed.

```bash
make build
```

1. Create signing key

   ```bash
    keytool -genkeypair \
      -keystore "$HOME/.android/papirus-icons-release.keystore" \
      -alias papirus-icons \
      -keyalg RSA \
      -keysize 4096 \
      -validity 10000
   ```

   Store the password and ~/.android/papirus-icons-release.keystore safely.

   Note: can use same password for both keystore and key.

2. Configure release signing

   ```bash
   cp signing.properties.example signing.properties
   ```

   Rename `signing.properties.example` to `signing.properties` and fill USERNAME, KEYSTORE_PASSWORD and KEY_PASSWORD.

   Note: `signing.properties` is git ignored.

3. Assemble release APK

   ```bash
   ./gradlew assembleRelease
   ```

   The signed release APK is written in `app/build/outputs/apk/release/`.

   Note: VSC task available.

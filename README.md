<p align="center">
  <img src="https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus_icons/master/preview.png" alt="preview"/>
</p>

# Papirus Icon Pack
Popular Linux icon theme now on Android!

# Fork

This is a fork of [Papirus Android icon pack repo](https://github.com/PapirusDevelopmentTeam/papirus_icons/tree/master/scripts) which is outdated and not kept up to date with upstream [Papirus icon theme repo](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme).
At time or writing last release [available on opendesktop.org](https://www.opendesktop.org/p/1662847/) is 20220220.

This fork adds an update script that pulls icons from the upstream repo.


# Supported Launchers:
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

# Features:
- Fully Open Source
- Pixel perfect
- More than 1500 icons
- Inspired by Material design
- Icon Request option
- Check Update function
- 8 Cloud Wallpapers

# Sync current Papirus icons

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
- VSC (VS Code & Codium) task available

# Build debug APK

make build after changing icons or data.json; then run Gradle to create the APK.

1. Build icon resources
   ```bash
    make build
   ```
   - checks data.json and SVG icon filenames;
   - converts the SVG files in src/ into PNG files in app/src/main/res/drawable-nodpi/;
   - generates appfilter.xml, which maps Android app activities from data.json to icon names;
   - generates drawable.xml, the list of icons shown by the icon-pack app.

2. Assemble debug APK
   ```bash
   ./gradlew assembleDebug
   ```

   takes those generated PNG/XML resources plus the Android app code and compiles them into a debug APK, written in `app/build/outputs/apk/debug/`.


Notes:
- VSC tasks available
- Nix shell is provided with dependencies: Java 11, Android API 31, Android build tools and the icon conversion tools. VSC shell tasks should load this shell with direnv automatically. Run `direnv allow` once after cloning this project or changing `.envrc`.

# Build release APK

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

   Rename `signing.properties.example` to `signing.properties` and fill USERNAME, KEYSTORE_PASSWORD and KEY_PASSWORD.

   Note: can use same password for both keystore and key.


# Install
You can [download icon pack](https://www.pling.com/p/1662847/) directly from the Android browser or download on PC and send to phone via KDE Connect/Send Anywhere/Android File Transfer or adb.
Application have "Check Update" button for features updates.

# Priority icon requests:
1. If you donate
2. Popular applications
3. Open source applications
4. Games

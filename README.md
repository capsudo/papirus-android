<p align="center">
  <img src="https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus_icons/master/preview.png" alt="preview"/>
</p>

# Papirus Icon Pack
Popular Linux icon theme now on Android!

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


# Install
You can [download icon pack](https://www.pling.com/p/1662847/) directly from the Android browser or download on PC and send to phone via KDE Connect/Send Anywhere/Android File Transfer or adb.
Application have "Check Update" button for features updates.

# Priority icon requests:
1. If you donate
2. Popular applications
3. Open source applications
4. Games

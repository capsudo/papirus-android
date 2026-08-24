{ pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true; # Android SDK package is unfree.
      android_sdk.accept_license = true; # User accepted Android SDK licence for this project.
    };
  }
}:

let
  androidSdk = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "31" ];
    buildToolsVersions = [ "31.0.0" ];
  };
in
pkgs.mkShell {
  packages = [
    pkgs.bash # update icons: script interpreter
    pkgs.coreutils # update icons: cp, mkdir, mv and rm.
    pkgs.findutils # update icons: find
    pkgs.diffutils #  # update icons: cmp
    pkgs.git #  # update icons: git clone/pull
    androidSdk.androidsdk # build apk: Android API 31 and build tools 31.0.0
    pkgs.inkscape # build apk: convert SVG icons to PNG files
    pkgs.jdk11_headless # build apk: Java version required by Gradle 7.0.2 and Android Gradle Plugin 7.0.4
    pkgs.gnumake # build apk: run Makefile to validate icons and generate Android XML files
    pkgs.jq # build apk: validate and format data.json
    pkgs.python3 # build apk: generate appfilter.xml from data.json
  ];

  ANDROID_HOME = "${androidSdk.androidsdk}/libexec/android-sdk"; # Gradle: Android SDK path
  ANDROID_SDK_ROOT = "${androidSdk.androidsdk}/libexec/android-sdk"; # Gradle: Android SDK path
  JAVA_HOME = "${pkgs.jdk11_headless}"; # Gradle: Java 11 path

  shellHook = ''
    echo "Papirus Android build shell: run make build, then ./gradlew assembleDebug"
  '';
}

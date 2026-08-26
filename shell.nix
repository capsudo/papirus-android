{ pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true; # Android SDK package is unfree.
      android_sdk.accept_license = true; # User accepted Android SDK licence for this project.
    };
  }
}:

let
  androidSdk = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "36" ]; # Android platform (API) CandyBar 3.23 compiles against and targets.
    buildToolsVersions = [ "36.0.0" ]; # Programs Gradle uses to compile/package APK files.
  };
in
pkgs.mkShell {
  packages = [
    pkgs.bash # update icons: script interpreter
    pkgs.coreutils # update icons: cp, mkdir, mv and rm.
    pkgs.findutils # update icons: find
    pkgs.diffutils #  # update icons: cmp
    pkgs.git #  # update icons: git clone/pull
    pkgs.gh # create GitHub release from VSC task
    androidSdk.androidsdk # build apk: Android API 36 and build tools 36.0.0
    pkgs.inkscape # build apk: convert SVG icons to PNG files
    pkgs.jdk17_headless # build apk: Java version required by Gradle 9.4.1 and Android Gradle Plugin 9.2.1
    pkgs.gnumake # build apk: run Makefile to validate icons and generate Android XML files
    pkgs.jq # build apk: validate and format data.json
    pkgs.python3 # build apk: generate appfilter.xml from data.json
  ];

  ANDROID_HOME = "${androidSdk.androidsdk}/libexec/android-sdk"; # Gradle: Android SDK path
  ANDROID_SDK_ROOT = "${androidSdk.androidsdk}/libexec/android-sdk"; # Gradle: Android SDK path
  JAVA_HOME = "${pkgs.jdk17_headless}"; # Gradle: Java 17 path
  GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidSdk.androidsdk}/libexec/android-sdk/build-tools/36.0.0/aapt2"; # Make Gradle use Nix AAPT2 because its installation directory cannot be modified.
  shellHook = ''
    echo "Papirus Android build shell: run make build, then ./gradlew assembleDebug"
  '';
}

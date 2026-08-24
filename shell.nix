{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = [
    pkgs.bash # update_icons interpreter
    pkgs.coreutils # update_icons: cp, mkdir, mv and rm.    
    pkgs.findutils # update_icons: find
    pkgs.diffutils #  # update_icons: cmp
    pkgs.git #  # update_icons: git clone/pull
  ];

  shellHook = ''
    # This shell only contains tools needed to synchronize SVG icons.
    # Android SDK, Java, Gradle and APK build tools will be added later when APK builds are configured.
    echo "Papirus Android sync shell: run scripts/update_icons.sh --dry-run"
  '';
}

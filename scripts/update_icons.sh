#!/usr/bin/env bash

set -euo pipefail
LC_ALL=C

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIRECTORY="$(cd -- "$SCRIPT_DIRECTORY/.." && pwd)"

# Download current icons from the official Papirus icon theme Git repository.
PAPIRUS_ICON_THEME_REPOSITORY_URL="https://github.com/PapirusDevelopmentTeam/papirus-icon-theme.git"

# Keep a shallow Git checkout inside this project so each later sync can download only new changes.
# This directory is ignored by Git and is not included in commits of the Android icon pack.
PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY="${PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY:-$PROJECT_DIRECTORY/.cache/papirus-icon-theme}"
PAPIRUS_APPLICATION_ICONS_DIRECTORY=""
ANDROID_ICON_SOURCE_DIRECTORY="$PROJECT_DIRECTORY/src"
IS_DRY_RUN=false

print_usage() {
    cat <<'EOF'
Usage: scripts/update_icons.sh [--dry-run] [--checkout-dir DIRECTORY]

Copy current Papirus 64x64 application SVGs directly into src.
An existing src SVG with the same Android resource name is replaced. Existing
src SVGs that Papirus no longer provides are left unchanged.
EOF
}

while (($# > 0)); do
    case "$1" in
        --dry-run)
            IS_DRY_RUN=true
            ;;
        --checkout-dir)
            PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY="${2:?--checkout-dir requires a directory}"
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n\n' "$1" >&2
            print_usage >&2
            exit 2
            ;;
    esac
    shift
done

if ! command -v git >/dev/null; then
    printf 'Git is required to download Papirus icons. Enter the Nix shell with nix-shell and try again.\n' >&2
    exit 1
fi

update_papirus_icon_theme_checkout() {
    if [[ -d "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY/.git" ]]; then
        # Fast-forward only prevents the script from changing a checkout that has local commits or conflicts.
        printf 'Downloading new Papirus icon changes.\n'
        git -C "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY" pull --ff-only
    elif [[ -d "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY" ]] && [[ -z "$(find "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        # A failed first clone can leave an empty directory. Remove only that empty directory before trying again.
        rmdir "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY"
        printf 'Downloading Papirus icons for the first time.\n'
        git clone --depth 1 "$PAPIRUS_ICON_THEME_REPOSITORY_URL" "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY"
    elif [[ -e "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY" ]]; then
        printf 'Papirus checkout path exists but is not a Git checkout: %s\n' \
            "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY" >&2
        exit 1
    else
        # The first sync creates a small shallow checkout because only current icon files are needed.
        printf 'Downloading Papirus icons for the first time.\n'
        mkdir -p "$(dirname -- "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY")"
        git clone --depth 1 "$PAPIRUS_ICON_THEME_REPOSITORY_URL" "$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY"
    fi
}

update_papirus_icon_theme_checkout

PAPIRUS_APPLICATION_ICONS_DIRECTORY="$PAPIRUS_ICON_THEME_CHECKOUT_DIRECTORY/Papirus/64x64/apps"

if [[ ! -d "$PAPIRUS_APPLICATION_ICONS_DIRECTORY" ]]; then
    printf 'Papirus application icon directory does not exist: %s\n' \
        "$PAPIRUS_APPLICATION_ICONS_DIRECTORY" >&2
    exit 1
fi

normalize_icon_filename() {
    local source_filename="$1"
    local source_filename_without_extension
    local normalized_character
    local normalized_filename_without_extension=""
    local filename_character_index

    source_filename_without_extension="${source_filename%.svg}"
    source_filename_without_extension="${source_filename_without_extension,,}"

    for ((filename_character_index = 0; filename_character_index < ${#source_filename_without_extension}; filename_character_index += 1)); do
        normalized_character="${source_filename_without_extension:filename_character_index:1}"
        if [[ "$normalized_character" =~ [a-z0-9] ]]; then
            normalized_filename_without_extension+="$normalized_character"
        elif [[ "$normalized_filename_without_extension" != *_ ]]; then
            normalized_filename_without_extension+="_"
        fi
    done

    normalized_filename_without_extension="${normalized_filename_without_extension%_}"

    # Every copied icon is placed in Apps category and starts with a valid Android resource prefix.
    printf 'apps_%s.svg' "$normalized_filename_without_extension"
}

declare -A papirus_icon_paths_by_android_filename=()

while IFS= read -r -d '' source_icon_path; do
    source_icon_filename="${source_icon_path##*/}"
    android_icon_filename="$(normalize_icon_filename "$source_icon_filename")"

    if [[ -v "papirus_icon_paths_by_android_filename[$android_icon_filename]" ]]; then
        existing_source_icon_path="${papirus_icon_paths_by_android_filename[$android_icon_filename]}"
        existing_source_icon_filename="${existing_source_icon_path##*/}"

        # Android resource names ignore filename case. Prefer normal lowercase file when Papirus has both names.
        if [[ "$source_icon_filename" =~ ^[a-z0-9] && ! "$existing_source_icon_filename" =~ ^[a-z0-9] ]]; then
            papirus_icon_paths_by_android_filename[$android_icon_filename]="$source_icon_path"
            printf 'Using %s instead of case-variant %s for %s\n' \
                "$source_icon_filename" "$existing_source_icon_filename" "$android_icon_filename" >&2
        else
            printf 'Skipping case-variant %s because it also normalizes to %s\n' \
                "$source_icon_filename" "$android_icon_filename" >&2
        fi
    else
        papirus_icon_paths_by_android_filename[$android_icon_filename]="$source_icon_path"
    fi
done < <(find "$PAPIRUS_APPLICATION_ICONS_DIRECTORY" -maxdepth 1 -type f -name '*.svg' -print0)

if ((${#papirus_icon_paths_by_android_filename[@]} == 0)); then
    printf 'No SVG icons found in %s\n' "$PAPIRUS_APPLICATION_ICONS_DIRECTORY" >&2
    exit 1
fi

added_icon_count=0
updated_icon_count=0
unchanged_icon_count=0

run_change() {
    if $IS_DRY_RUN; then
        printf 'Would'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

for android_icon_filename in "${!papirus_icon_paths_by_android_filename[@]}"; do
    source_icon_path="${papirus_icon_paths_by_android_filename[$android_icon_filename]}"
    destination_icon_path="$ANDROID_ICON_SOURCE_DIRECTORY/$android_icon_filename"

    # Existing icon with this name is replaced by the current Papirus version.
    if [[ -f "$destination_icon_path" ]] && cmp -s "$source_icon_path" "$destination_icon_path"; then
        ((unchanged_icon_count += 1))
    elif [[ -f "$destination_icon_path" ]]; then
        run_change cp --preserve=mode,timestamps -- "$source_icon_path" "$destination_icon_path"
        ((updated_icon_count += 1))
    else
        run_change cp --preserve=mode,timestamps -- "$source_icon_path" "$destination_icon_path"
        ((added_icon_count += 1))
    fi
done

printf 'Papirus icons: %d added, %d updated, %d unchanged. Existing icons without a current Papirus match were kept.\n' \
    "$added_icon_count" "$updated_icon_count" "$unchanged_icon_count"

if "$IS_DRY_RUN"; then
    printf 'Dry run only; no Android SVG files were changed. The Papirus Git checkout may have been downloaded or updated.\n'
fi

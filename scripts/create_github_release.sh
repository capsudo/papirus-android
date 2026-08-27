#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_BUILD_FILE="$PROJECT_DIRECTORY/app/build.gradle"
CHANGELOG_FILE="$PROJECT_DIRECTORY/app/src/main/res/values/changelog.xml"
RELEASE_APK_DIRECTORY="$PROJECT_DIRECTORY/app/build/outputs/apk/release"
RELEASE_METADATA_FILE="$RELEASE_APK_DIRECTORY/output-metadata.json"
UPDATE_CONFIGURATION_FILE="$PROJECT_DIRECTORY/update.json"
UPDATE_CONFIGURATION_BRANCH="master"

fail() {
    printf 'Cannot create GitHub release: %s\n' "$1" >&2
    exit 1
}

read_release_input() {
    local input_label="$1"
    local input_value=""

    read -r -p "$input_label" input_value
    printf '%s' "$input_value"
}

read_gradle_versions() {
    mapfile -t gradle_version_codes < <(
        sed -nE 's/^[[:space:]]*versionCode[[:space:]]+([0-9]+)[[:space:]]*$/\1/p' \
            "$GRADLE_BUILD_FILE"
    )
    mapfile -t gradle_version_names < <(
        sed -nE 's/^[[:space:]]*versionName[[:space:]]+"([^"]+)"[[:space:]]*$/\1/p' \
            "$GRADLE_BUILD_FILE"
    )

    if [ "${#gradle_version_codes[@]}" -ne 1 ] || [ "${#gradle_version_names[@]}" -ne 1 ]; then
        fail "could not read one versionCode and versionName from app/build.gradle"
    fi

    gradle_version_code="${gradle_version_codes[0]}"
    gradle_version_name="${gradle_version_names[0]}"
}

escape_android_xml_text() {
    # Returns XML text so release messages such as "A & B" remain valid in changelog.xml.
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<< "$1"
}

cd "$PROJECT_DIRECTORY"

release_title=""
release_message=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --release-title)
            [ "$#" -ge 2 ] || fail "--release-title needs a value"
            release_title="$2"
            shift 2
            ;;
        --release-message)
            [ "$#" -ge 2 ] || fail "--release-message needs a value"
            release_message="$2"
            shift 2
            ;;
        *)
            fail "unknown argument $1"
            ;;
    esac
done

# Direct script use asks in terminal. VS Code supplies both values through task inputs.
if [ -z "$release_title" ]; then
    release_title="$(read_release_input 'Release title/versionName (example: 20260801.4): ')"
fi
if [ -z "$release_message" ]; then
    release_message="$(read_release_input 'Release message (use \\n for a new line): ')"
fi

# VS Code promptString is single-line. Convert its literal \n marker into release-message lines.
release_message="${release_message//\\n/$'\n'}"

if [[ ! "$release_title" =~ ^[0-9A-Za-z._-]+$ ]]; then
    fail "release title must contain only letters, digits, dot, underscore or hyphen"
fi
if ! grep -q '[^[:space:]]' <<< "$release_message"; then
    fail "release message cannot be empty"
fi

release_tag="v$release_title"

# This script replaces version fields and commits them, so it needs no unrelated local changes.
if [ -n "$(git status --porcelain)" ]; then
    fail "commit or remove local changes first"
fi

# Update metadata must reach master because CandyBar downloads update.json from that branch.
current_git_branch_name="$(git branch --show-current)"
if [ "$current_git_branch_name" != "$UPDATE_CONFIGURATION_BRANCH" ]; then
    fail "check out $UPDATE_CONFIGURATION_BRANCH before creating a release"
fi

# Refuse both local and remote tag collisions before creating release commit.
if ! git check-ref-format "refs/tags/$release_tag"; then
    fail "$release_tag is not a valid Git tag"
fi
if git show-ref --tags --verify --quiet "refs/tags/$release_tag"; then
    fail "local tag $release_tag already exists"
fi
if ! remote_tag_references="$(git ls-remote --tags origin "refs/tags/$release_tag")"; then
    fail "could not read tags from origin"
fi
if [ -n "$remote_tag_references" ]; then
    fail "tag $release_tag already exists on origin"
fi

# GitHub CLI needs owner/repository when no default repository is configured.
origin_repository_url="$(git remote get-url origin 2>/dev/null || true)"
case "$origin_repository_url" in
    https://github.com/*)
        github_repository="${origin_repository_url#https://github.com/}"
        ;;
    git@github.com:*)
        github_repository="${origin_repository_url#git@github.com:}"
        ;;
    ssh://git@github.com/*)
        github_repository="${origin_repository_url#ssh://git@github.com/}"
        ;;
    *)
        fail "origin must be a github.com owner/repository URL"
        ;;
esac
github_repository="${github_repository%.git}"

if ! command -v gh >/dev/null; then
    fail "GitHub CLI is missing; enter Nix shell again after pulling this change"
fi

if ! gh auth status >/dev/null 2>&1; then
    fail "sign in first with gh auth login"
fi

# Avoid making release changes when the requested GitHub release already exists.
if gh release view "$release_tag" --repo "$github_repository" >/dev/null 2>&1; then
    fail "GitHub release $release_tag already exists"
fi

# Update both version fields together: versionCode must always increase, versionName is release title.
read_gradle_versions
next_gradle_version_code="$((10#$gradle_version_code + 1))"
release_changelog_xml_text="$(escape_android_xml_text "$release_message")"

temporary_gradle_build_file="$(mktemp)"
RELEASE_VERSION_CODE="$next_gradle_version_code" \
RELEASE_VERSION_NAME="$release_title" \
awk '
    BEGIN {
        release_version_code = ENVIRON["RELEASE_VERSION_CODE"]
        release_version_name = ENVIRON["RELEASE_VERSION_NAME"]
    }
    /^[[:space:]]*versionCode[[:space:]]+[0-9]+[[:space:]]*$/ {
        version_code_replacements++
        updated_line = $0
        sub(/[0-9]+[[:space:]]*$/, release_version_code, updated_line)
        print updated_line
        next
    }
    /^[[:space:]]*versionName[[:space:]]+"[^"]+"[[:space:]]*$/ {
        version_name_replacements++
        updated_line = $0
        sub(/"[^"]+"[[:space:]]*$/, "\"" release_version_name "\"", updated_line)
        print updated_line
        next
    }
    { print }
    END {
        if (version_code_replacements != 1 || version_name_replacements != 1) {
            print "Expected one versionCode and one versionName in app/build.gradle" > "/dev/stderr"
            exit 1
        }
    }
 ' "$GRADLE_BUILD_FILE" > "$temporary_gradle_build_file"
mv "$temporary_gradle_build_file" "$GRADLE_BUILD_FILE"

# CandyBar reads this bundled XML for its first-launch "What's new" dialog.
temporary_changelog_file="$(mktemp)"
RELEASE_CHANGELOG_XML_TEXT="$release_changelog_xml_text" \
awk '
    BEGIN {
        changelog_xml_text = ENVIRON["RELEASE_CHANGELOG_XML_TEXT"]
    }
    /<string-array[[:space:]]+name="changelog">/ {
        changelog_replacements++
        in_changelog_array = 1
        print
        print "        <item>" changelog_xml_text "</item>"
        next
    }
    /<\/string-array>/ && in_changelog_array {
        in_changelog_array = 0
        print
        next
    }
    !in_changelog_array { print }
    END {
        if (changelog_replacements != 1 || in_changelog_array) {
            print "Expected one complete changelog string-array in changelog.xml" > "/dev/stderr"
            exit 1
        }
    }
 ' "$CHANGELOG_FILE" > "$temporary_changelog_file"
mv "$temporary_changelog_file" "$CHANGELOG_FILE"

git diff --check
git add "$GRADLE_BUILD_FILE" "$CHANGELOG_FILE"
git commit -m "version bump for release $release_tag"

# Build after committing release metadata, so the APK contains exactly the tagged version.
./gradlew assembleRelease

read_gradle_versions
if [ "$gradle_version_code" != "$next_gradle_version_code" ] || [ "$gradle_version_name" != "$release_title" ]; then
    fail "Gradle version changed while preparing $release_tag"
fi

# Metadata comes from the build above and names the exact APK, even if older APKs remain in build/.
if [ ! -f "$RELEASE_METADATA_FILE" ]; then
    fail "release build did not produce output-metadata.json"
fi
metadata_version_code="$(jq -r '.elements[0].versionCode // empty' "$RELEASE_METADATA_FILE")"
metadata_version_name="$(jq -r '.elements[0].versionName // empty' "$RELEASE_METADATA_FILE")"
metadata_apk_filename="$(jq -r '.elements[0].outputFile // empty' "$RELEASE_METADATA_FILE")"
release_apk_path="$RELEASE_APK_DIRECTORY/$metadata_apk_filename"

if [ "$metadata_version_code" != "$gradle_version_code" ] || \
    [ "$metadata_version_name" != "$gradle_version_name" ] || \
    [ ! -f "$release_apk_path" ]; then
    fail "APK metadata does not match versionCode $gradle_version_code and versionName $gradle_version_name"
fi

# An annotated tag stores the same message used by GitHub, update.json and the in-app changelog.
git tag --annotate "$release_tag" --message "$release_message"
git push origin "$UPDATE_CONFIGURATION_BRANCH" "$release_tag"

# CandyBar downloads this file after installation to get version, download URL and notes.
if [ ! -f "$UPDATE_CONFIGURATION_FILE" ]; then
    fail "update.json is missing"
fi
if ! jq -e 'type == "object"' "$UPDATE_CONFIGURATION_FILE" >/dev/null; then
    fail "update.json is not a JSON object"
fi

printf 'Creating GitHub release %s with %s\n' "$release_tag" "${release_apk_path##*/}"
gh release create "$release_tag" "$release_apk_path" \
    --repo "$github_repository" \
    --title "$release_title" \
    --notes "$release_message" \
    --verify-tag

# Update update.json
# GitHub release exists now, so latest/download resolves to uploaded APK.
release_download_url="https://github.com/$github_repository/releases/latest/download/$metadata_apk_filename"
temporary_update_configuration_file="$(mktemp)"
trap 'rm -f "$temporary_update_configuration_file"' EXIT

jq \
    --arg latest_version "$gradle_version_name" \
    --argjson latest_version_code "$gradle_version_code" \
    --arg release_download_url "$release_download_url" \
    --arg release_notes "$release_message" \
    '.latestVersion = $latest_version |
     .latestVersionCode = $latest_version_code |
     .url = $release_download_url |
     .releaseNotes = ($release_notes | split("\\n") | map(gsub("\\r$"; "") | select(length > 0)))' \
    "$UPDATE_CONFIGURATION_FILE" > "$temporary_update_configuration_file"
mv "$temporary_update_configuration_file" "$UPDATE_CONFIGURATION_FILE"

# Commit and push it to master so it is available at URL checked by CandyBar check-update
git add "$UPDATE_CONFIGURATION_FILE"
# Publish config in follow-up commit so it never points at APK before GitHub upload succeeds.
git commit -m "update after release $release_tag published"
git push origin "$UPDATE_CONFIGURATION_BRANCH"

#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_BUILD_FILE="$PROJECT_DIRECTORY/app/build.gradle"
RELEASE_APK_DIRECTORY="$PROJECT_DIRECTORY/app/build/outputs/apk/release"
RELEASE_METADATA_FILE="$RELEASE_APK_DIRECTORY/output-metadata.json"
UPDATE_CONFIGURATION_FILE="$PROJECT_DIRECTORY/update.json"
UPDATE_CONFIGURATION_BRANCH="master"

fail() {
    printf 'Cannot create GitHub release: %s\n' "$1" >&2
    exit 1
}

cd "$PROJECT_DIRECTORY"

# Release tag must include every committed release change.
if [ -n "$(git status --porcelain)" ]; then
    fail "commit or remove local changes first"
fi

# Update metadata must reach master because CandyBar downloads update.json from that branch.
current_git_branch_name="$(git branch --show-current)"
if [ "$current_git_branch_name" != "$UPDATE_CONFIGURATION_BRANCH" ]; then
    fail "check out $UPDATE_CONFIGURATION_BRANCH before creating a release"
fi

# Read versions from Gradle because these values also identify generated APK.
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
release_tag="v$gradle_version_name"
latest_release_tag="$(git for-each-ref --count=1 --sort=-version:refname \
    --format='%(refname:short)' 'refs/tags/v*')"

# Latest release tag and Gradle version must describe same release.
if [ "$latest_release_tag" != "$release_tag" ]; then
    fail "versionName $gradle_version_name does not match latest release tag $latest_release_tag"
fi

tag_object_type="$(git for-each-ref --format='%(objecttype)' "refs/tags/$release_tag")"
if [ "$tag_object_type" != "tag" ]; then
    fail "$release_tag must be an annotated tag so its message can become release notes"
fi

# Local and origin tags must identify same release commit.
tag_commit="$(git rev-parse "$release_tag^{}")"

release_notes="$(git for-each-ref --format='%(contents)' "refs/tags/$release_tag")"
if ! grep -q '[^[:space:]]' <<< "$release_notes"; then
    fail "$release_tag needs a tag message for release notes"
fi

# GitHub release must use tag already available on origin.
if ! remote_tag_references="$(git ls-remote --tags origin "refs/tags/$release_tag*")"; then
    fail "could not read tags from origin"
fi

remote_tag_commit="$(printf '%s\n' "$remote_tag_references" | awk \
    -v remote_tag_reference="refs/tags/$release_tag^{}" \
    '$2 == remote_tag_reference { print $1 }')"
if [ "$remote_tag_commit" != "$tag_commit" ]; then
    fail "$release_tag on origin does not match local release tag"
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

# Avoid replacing an existing release asset by accident.
if gh release view "$release_tag" --repo "$github_repository" >/dev/null 2>&1; then
    fail "GitHub release $release_tag already exists"
fi

shopt -s nullglob
release_apk_paths=("$RELEASE_APK_DIRECTORY"/*.apk)
if [ "${#release_apk_paths[@]}" -ne 1 ]; then
    fail "expected exactly one APK in app/build/outputs/apk/release"
fi

release_apk_path="${release_apk_paths[0]}"
if [ ! -f "$RELEASE_METADATA_FILE" ]; then
    fail "build release APK first; output-metadata.json is missing"
fi

# Check update.json
# CandyBar downloads this file after installation to get update version, download URL and notes.
if [ ! -f "$UPDATE_CONFIGURATION_FILE" ]; then
    fail "update.json is missing"
fi

if ! jq -e 'type == "object"' "$UPDATE_CONFIGURATION_FILE" >/dev/null; then
    fail "update.json is not a JSON object"
fi

# Metadata comes from same Gradle build as APK and contains its output filename.
metadata_version_code="$(jq -r '.elements[0].versionCode // empty' "$RELEASE_METADATA_FILE")"
metadata_version_name="$(jq -r '.elements[0].versionName // empty' "$RELEASE_METADATA_FILE")"
metadata_apk_filename="$(jq -r '.elements[0].outputFile // empty' "$RELEASE_METADATA_FILE")"

if [ "$metadata_version_code" != "$gradle_version_code" ] || \
    [ "$metadata_version_name" != "$gradle_version_name" ] || \
    [ "$metadata_apk_filename" != "${release_apk_path##*/}" ]; then
    fail "APK metadata does not match versionCode $gradle_version_code and versionName $gradle_version_name"
fi

printf 'Creating GitHub release %s with %s\n' "$release_tag" "${release_apk_path##*/}"
gh release create "$release_tag" "$release_apk_path" \
    --repo "$github_repository" \
    --title "$release_tag" \
    --notes "$release_notes" \
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
    --arg release_notes "$release_notes" \
    '.latestVersion = $latest_version |
     .latestVersionCode = $latest_version_code |
     .url = $release_download_url |
     .releaseNotes = ($release_notes | split("\\n") | map(gsub("\\r$"; "") | select(length > 0)))' \
    "$UPDATE_CONFIGURATION_FILE" > "$temporary_update_configuration_file"
mv "$temporary_update_configuration_file" "$UPDATE_CONFIGURATION_FILE"

# Commit and push it to master so it is available at URL checked by CandyBar check-update
git add "$UPDATE_CONFIGURATION_FILE"
# Publish config in follow-up commit so it never points at APK before GitHub upload succeeds.
git commit -m "Update in-app update metadata for $release_tag"
git push origin "$UPDATE_CONFIGURATION_BRANCH"

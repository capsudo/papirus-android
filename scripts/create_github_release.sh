#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_BUILD_FILE="$PROJECT_DIRECTORY/app/build.gradle"
RELEASE_APK_DIRECTORY="$PROJECT_DIRECTORY/app/build/outputs/apk/release"
RELEASE_METADATA_FILE="$RELEASE_APK_DIRECTORY/output-metadata.json"

fail() {
    printf 'Cannot create GitHub release: %s\n' "$1" >&2
    exit 1
}

cd "$PROJECT_DIRECTORY"

# Release tag must include every committed release change.
if [ -n "$(git status --porcelain)" ]; then
    fail "commit or remove local changes first"
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

# Release tag must point at current commit, not an earlier release commit.
head_commit="$(git rev-parse HEAD)"
tag_commit="$(git rev-parse "$release_tag^{}")"
if [ "$tag_commit" != "$head_commit" ]; then
    fail "$release_tag must point at current commit $head_commit"
fi

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
if [ "$remote_tag_commit" != "$head_commit" ]; then
    fail "$release_tag is not pushed to origin at current commit"
fi

if ! command -v gh >/dev/null; then
    fail "GitHub CLI is missing; enter Nix shell again after pulling this change"
fi

if ! gh auth status >/dev/null 2>&1; then
    fail "sign in first with gh auth login"
fi

# Avoid replacing an existing release asset by accident.
if gh release view "$release_tag" >/dev/null 2>&1; then
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
    --title "$release_tag" \
    --notes "$release_notes" \
    --verify-tag

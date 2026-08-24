#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
INKSCAPE_VERSION=$(inkscape --version 2>/dev/null | awk '/Inkscape[ ]/ {print $2; exit}')

: "${DEST_DIR:="$SCRIPT_DIR"/../app/src/main/res/drawable-nodpi}"
: "${SRC_DIR:="$SCRIPT_DIR"/../src}"
: "${ICON_SIZE:=192}"
: "${THREADS:=$(nproc)}"

report_completed_icon() {
	# Every xargs worker writes one line after it has converted or skipped one icon.
	# This output is read by show_conversion_progress after xargs starts all workers.
	printf '\n'
}

do_convert_to_png() {
	local file="$1"
	local bitmap_file svg_mtime png_mtime

	bitmap_file="${DEST_DIR}/$(basename -- "$file" .svg).png"

	if [ -f "$bitmap_file" ]; then
		svg_mtime="$(stat -c '%Y' "$file")"
		png_mtime="$(stat -c '%Y' "$bitmap_file")"

		if (( png_mtime > svg_mtime )); then
			# exit when PNG file exists and the modification time is
			# newer than on SVG file
			report_completed_icon
			return 0
		fi
	fi

	if [ "${INKSCAPE_VERSION%%.*}" -eq 0 ]; then
		inkscape -z -w "$ICON_SIZE" -h "$ICON_SIZE" -e "$bitmap_file" "$file" >/dev/null
	else
		inkscape -w "$ICON_SIZE" -h "$ICON_SIZE" -o "$bitmap_file" "$file" >/dev/null
	fi

	report_completed_icon
}

show_conversion_progress() {
	local completed_icon_count=0
	local progress_percentage

	while IFS= read -r _; do
		((completed_icon_count += 1))
		progress_percentage=$((completed_icon_count * 100 / ICON_FILE_COUNT))
		printf '\rIcons converted to PNG: %d/%d (%d%%)' \
			"$completed_icon_count" "$ICON_FILE_COUNT" "$progress_percentage" >&2
	done

	printf '\n' >&2
}

ICON_FILE_COUNT=$(find "$SRC_DIR" -maxdepth 1 -type f -name '*.svg' | wc -l)

if [ "$ICON_FILE_COUNT" -eq 0 ]; then
	printf 'No SVG icon files found in %s\n' "$SRC_DIR" >&2
	exit 1
fi

mkdir -p "$DEST_DIR"

# xargs starts a new Bash process for every icon, so it needs this value to select the right Inkscape command-line syntax.
export DEST_DIR ICON_SIZE INKSCAPE_VERSION
export -f do_convert_to_png report_completed_icon

# Each worker prints one empty line after it has converted or skipped its icon.
# This function counts those lines and displays one progress line while xargs continues running workers.
find "$SRC_DIR" -maxdepth 1 -name '*.svg' -print0 |
	xargs -0 -I {} -P "$THREADS" bash -c 'do_convert_to_png "$@"' _ {} |
	show_conversion_progress

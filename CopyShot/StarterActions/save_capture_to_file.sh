#!/bin/sh
# @copyshot.id copyshot.save-capture-to-file
# @copyshot.title Save Capture to File
# @copyshot.description Save exact text to a new file in Documents/CopyShot Captures; keep the clipboard unchanged.
# @copyshot.icon doc.badge.plus
# @copyshot.modes standardOCR, qrBarcode, latex, table
# @copyshot.output none
# @copyshot.timeout 30

# A custom directory can be supplied by an external caller. In CopyShot,
# edit the default below to choose another folder. No extra runtime is needed.
capture_directory=${COPYSHOT_EXPORT_DIRECTORY:-"$HOME/Documents/CopyShot Captures"}
umask 077

if ! /bin/mkdir -p "$capture_directory"; then
    printf 'Could not create the capture export folder: %s\n' "$capture_directory" >&2
    exit 1
fi

# A UUID distinguishes captures even when several are saved in one second.
# Noclobber creates the file exclusively, protecting any existing destination.
timestamp=$(/bin/date -u '+%Y-%m-%dT%H-%M-%SZ') || exit 1
capture_id=$(/usr/bin/uuidgen) || exit 1
capture_file="$capture_directory/capture-$timestamp-$capture_id.txt"
set -C
exec 3> "$capture_file"

# Read stdin directly: preserve empty text, Unicode, and trailing newlines.
# Captured shell syntax remains data and is never evaluated.
if ! /bin/cat >&3; then
    exec 3>&-
    /bin/rm -f "$capture_file"
    printf 'Could not write the capture file.\n' >&2
    exit 1
fi
exec 3>&-

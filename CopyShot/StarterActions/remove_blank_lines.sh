#!/bin/sh
# @copyshot.id copyshot.remove-blank-lines
# @copyshot.title Remove Blank Lines
# @copyshot.description Remove empty and whitespace-only lines from captured text.
# @copyshot.icon text.badge.minus
# @copyshot.modes standardOCR
# @copyshot.output copy
# @copyshot.timeout 30

exec /usr/bin/sed '/^[[:space:]]*$/d'

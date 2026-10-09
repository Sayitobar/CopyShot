#!/bin/sh
# @copyshot.id copyshot.strip-line-numbers
# @copyshot.title Strip Line Numbers
# @copyshot.description Remove leading line numbers followed by whitespace or a punctuation separator.
# @copyshot.icon list.number
# @copyshot.modes standardOCR
# @copyshot.output copy
# @copyshot.timeout 30

# Use on text containing line numbers: a leading year followed by a space is
# indistinguishable from a line number. Decimal values and dates remain intact.
exec /usr/bin/sed -E 's/^[[:blank:]]*[0-9]+([.):][[:blank:]]+|[[:blank:]]+)//'

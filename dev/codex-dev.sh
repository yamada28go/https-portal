#!/bin/sh
set -eu
# No implicit fallback to full access; see the environment guide.
exec codex --sandbox workspace-write --ask-for-approval on-request "$@"

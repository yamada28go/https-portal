#!/bin/sh
set -eu
if [ "$(id -u)" = 0 ]; then
  echo 'Run this environment as the dev user, not root.' >&2
  exit 1
fi
if [ ! -r /workspace/Gemfile ]; then
  echo 'Mount the https-portal checkout at /workspace.' >&2
  exit 1
fi
if [ ! -r /bundle ]; then
  echo '/bundle is not readable; check development volume permissions.' >&2
  exit 1
fi
exec "$@"

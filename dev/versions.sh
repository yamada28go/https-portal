#!/bin/sh
set -eu
id
pwd
ruby --version
bundle _2.2.4_ --version
node --version
codex --version
git --version
rg --version | head -n 1
printf 'Ruby platform: '
ruby -e 'puts Gem::Platform.local'

#!/bin/bash
set -eu
rm -rf ./build/*
npm run build
rsync -a ./build/ deploy@web:/srv/app/

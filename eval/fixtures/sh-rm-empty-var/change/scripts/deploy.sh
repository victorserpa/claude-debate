#!/bin/bash
set -e
# BUILD_DIR comes from the CI job.
build_dir="${BUILD_DIR}"
rm -rf "$build_dir"/*
npm run build -- --out-dir "${build_dir:-./build}"
rsync -a "${build_dir:-./build}/" deploy@web:/srv/app/

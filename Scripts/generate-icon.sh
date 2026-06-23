#!/usr/bin/env bash
# Regenerate app icon assets from the shared BrandMark geometry.
# Run from the repo root.
swift run Decaffeinate --icon "${1:-assets}"

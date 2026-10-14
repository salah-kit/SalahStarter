#!/usr/bin/env bash
# Lints the Swift sources with the shared .swift-format configuration, as CI does.
# Fix findings with `swift format --in-place --recursive <paths>`.

set -euo pipefail

cd "$(dirname "$0")/.."

paths=(SalahStarter SalahStarterWidget Shared SalahStarterTests SalahStarterUITests)
swift format lint --strict --recursive "${paths[@]}"
echo "swift format lint: no findings in ${paths[*]}"

#!/bin/bash
# Compiles Novra's core (no UI) with Tests/CoreTests.swift and runs the checks.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/novra-tests"
SOURCES=(Novra/Core/*.swift Novra/UI/*.swift Novra/Features/Uninstaller/AppCatalog.swift Novra/Features/Uninstaller/PathHints.swift
         Novra/Features/SmartScan/JunkScanner.swift Novra/Features/SmartScan/ProjectScanner.swift
         Novra/Features/SmartScan/CleanupRules.swift Novra/Features/SmartScan/ExtraScanners.swift
         Novra/Features/Toolkit/ShredderView.swift Novra/Features/Toolkit/Tool.swift)
swiftc -parse-as-library -O -o "$OUT" "${SOURCES[@]}" Tests/CoreTests.swift
NOVRA_HISTORY_PATH="$(dirname "$OUT")/history.json" "$OUT"

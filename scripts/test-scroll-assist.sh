#!/usr/bin/env bash
# ScrollAssist with real wheel events (qmltestrunner, offscreen): a list
# inside a scrolling page gets the wheel; the page outside it, and once the
# list is at its end.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
qtd=$(nix build --no-link --print-out-paths nixpkgs#qt6.qtdeclarative)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/widgets" "$t/tests"
cp "$here/shell/widgets/ScrollAssist.qml" "$t/widgets/"
cp "$here/tests/scroll-assist/tst_nested.qml" "$t/tests/"
printf 'pragma Singleton\nimport QtQuick\nQtObject { property bool dark: true }\n' > "$t/Theme.qml"
echo "singleton Theme 1.0 Theme.qml" > "$t/qmldir"
# A stand-in Quickshell module (ScrollAssist reads Quickshell.env).
mkdir -p "$t/Quickshell"
printf 'pragma Singleton\nimport QtQuick\nQtObject { function env(n) { return "" } }\n' > "$t/Quickshell/Quickshell.qml"
printf 'module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n' > "$t/Quickshell/qmldir"
cd "$t"
QML_IMPORT_PATH="$t:$qtd/lib/qt-6/qml" QML2_IMPORT_PATH="$t:$qtd/lib/qt-6/qml" QT_QPA_PLATFORM=offscreen "$qtd/bin/qmltestrunner" -input tests

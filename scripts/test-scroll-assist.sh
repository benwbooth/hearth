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
cd "$t"
QML_IMPORT_PATH="$qtd/lib/qt-6/qml" QML2_IMPORT_PATH="$qtd/lib/qt-6/qml" QT_QPA_PLATFORM=offscreen "$qtd/bin/qmltestrunner" -input tests

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
python3 - "$output/ThemePalette.swift" <<'EOF'
import sys
from pathlib import Path
text = Path("Sources/ParcApp/ThemeRenderer.swift").read_text()
marker = "@MainActor\nenum NativeInputDiagnostics"
if marker not in text:
    raise SystemExit("ThemeRenderer.swift no longer contains the palette slice marker")
Path(sys.argv[1]).write_text(text[:text.index(marker)])
EOF
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift "$output/ThemePalette.swift" \
    Sources/ParcApp/SadTabContent.swift Sources/ParcApp/SplitDropPlaceholderCard.swift Sources/ParcApp/SplitDropView.swift \
    Sources/ParcApp/ParcSplitView.swift Sources/ParcApp/SplitDropGeometry.swift Sources/ParcApp/PageCardShadow.swift \
    Sources/ParcApp/SplitMarginHandle.swift Sources/ParcApp/SplitPaneHighlight.swift Sources/ParcApp/SidebarIconCatalog.swift \
    tests/SplitDropCard/CardTests.swift -o "$output/check"
cp -R Resources/CustomInfoPicker "$output/CustomInfoPicker"
"$output/check"

#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.38.5"
FLUTTER_ROOT="${HOME}/flutter"

if [[ ! -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
  archive="${TMPDIR:-/tmp}/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  curl -fsSL \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    -o "${archive}"
  tar -xf "${archive}" -C "${HOME}"
fi

export PATH="${FLUTTER_ROOT}/bin:${PATH}"
flutter config --no-analytics
flutter pub get
flutter build web --release --no-wasm-dry-run

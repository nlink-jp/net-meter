# assets

**`AppIcon-1024.png`** (1024×1024 PNG) is the app icon source. It is drawn by
`swift scripts/gen-icon.swift`; change the script and regenerate rather than
editing the image.

`make build-app` runs `scripts/make-icns.sh` to generate `AppIcon.icns` into the
`.app` bundle's Resources. If this file is absent, the app still builds — just
without a custom icon (the Makefile prints a warning).

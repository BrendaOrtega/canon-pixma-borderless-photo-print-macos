#!/bin/bash
# Instala `fotos` en ~/.local/bin (binario universal: Intel y Apple Silicon).
# curl -fsSL https://raw.githubusercontent.com/BrendaOrtega/canon-pixma-borderless-photo-print-macos/main/install.sh | bash
set -euo pipefail
REPO=BrendaOrtega/canon-pixma-borderless-photo-print-macos
DIR="$HOME/.local/bin"
mkdir -p "$DIR"
echo "Descargando fotos..."
curl -fsSL "https://github.com/$REPO/releases/latest/download/fotos" -o "$DIR/fotos"
chmod +x "$DIR/fotos"
xattr -d com.apple.quarantine "$DIR/fotos" 2>/dev/null || true
case ":$PATH:" in
  *":$DIR:"*) ;;
  *) echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
     echo "Agregué ~/.local/bin a tu PATH. Abre una Terminal nueva." ;;
esac
echo "✓ Listo. Prueba: fotos --help"

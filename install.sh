#!/bin/bash
set -e

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="spawn-agent"
REPO="pcomans/spawn-subagent"

# Fall back to ~/.local/bin if /usr/local/bin isn't writable
if [ ! -w "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR"
fi

echo "Installing $SCRIPT_NAME to $INSTALL_DIR..."
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/spawn-agent.sh" -o "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
echo "✅ Installed $SCRIPT_NAME"

# Warn if install dir isn't on PATH
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "⚠️  $INSTALL_DIR is not in your PATH. Add it to your shell profile." ;;
esac

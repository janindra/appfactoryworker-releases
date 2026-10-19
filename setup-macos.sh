#!/bin/bash
# AppFactoryWorker — bootstrap nového macu.
#
# Spuštění (bez sudo; heslo si řekne jen instalace Homebrew, pokud chybí):
#   curl -fsSL https://raw.githubusercontent.com/janindra/appfactoryworker-releases/main/setup-macos.sh | bash
#
# Zdroj pravdy je setup-macos.sh v repu appfactoryworker; kopii v release repu
# synchronizuje CI při každém tagu. Skript je idempotentní — co už na stroji
# je, přeskočí; dá se pouštět opakovaně.
set -euo pipefail

step() { printf '\n\033[36m== %s\033[0m\n' "$1"; }
ok()   { printf '   \033[32m%s\033[0m\n' "$1"; }

step 'Homebrew'
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# brew nemusí být v PATH této session (čerstvá instalace, ne-login shell)
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$b" ] && eval "$("$b" shellenv)" && break
done
ok "brew $(brew --version | head -1)"

step 'Základní nástroje: git, Node.js, GitHub CLI, Railway CLI'
for f in git node gh railway; do
  if command -v "$f" >/dev/null 2>&1; then ok "$f: už je"; else brew install "$f"; ok "$f: nainstalováno"; fi
done

step 'yarn'
if command -v yarn >/dev/null 2>&1; then ok 'už je'
else corepack enable 2>/dev/null || npm install -g yarn; ok 'nainstalován'; fi

step 'Claude Code CLI'
CLAUDE_DIR="$HOME/.local/bin"
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$CLAUDE_DIR/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
case ":$PATH:" in *":$CLAUDE_DIR:"*) ;; *) export PATH="$CLAUDE_DIR:$PATH";; esac
if ! grep -qs '\.local/bin' "$HOME/.zshrc" 2>/dev/null; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
fi
command -v claude >/dev/null 2>&1 || { echo 'claude po instalaci nejde spustit — otevři nový terminál a spusť skript znovu'; exit 1; }
ok "claude $(claude --version)"

step 'Přihlášení (interaktivní — jediná část, kterou skript neudělá sám)'
if gh auth status >/dev/null 2>&1; then ok 'GitHub: přihlášeno'; else gh auth login </dev/tty; fi
if railway whoami >/dev/null 2>&1; then ok 'Railway: přihlášeno'
else
  echo '   Railway: přihlas se účtem ownera (workspace „Jan Indra'"'"'s Projects“).'
  railway login </dev/tty || true
fi
echo '   Claude: otevře se claude — přihlas se přes /login a ukonči přes /exit.'
printf '   Enter pro pokračování '
read -r _ </dev/tty || true
claude /login </dev/tty || true

step 'Playwright browsery (větší stahování, chvíli to trvá)'
npx playwright install

step 'Integrace Claude Code — Playwright MCP a Railway plugin'
# opakované spuštění může hlásit „already exists" — to není chyba
claude mcp add playwright -s user -- npx @playwright/mcp@latest --browser chrome --viewport-size 1440,900 || true
claude plugin marketplace add anthropics/claude-plugins-official || true
claude plugin install railway@claude-plugins-official || true
# Zeabur skončil — starý plugin pryč, ať ho worker nenabízí
claude plugin uninstall zeabur@zeabur >/dev/null 2>&1 || true

step 'AppFactoryWorker — stažení a instalace'
API='https://api.github.com/repos/janindra/appfactoryworker-releases/releases/latest'
ARCH="$(uname -m)"   # arm64 / x86_64
URLS="$(curl -fsSL "$API" | grep -o 'https://[^"]*\.dmg')"
if [ "$ARCH" = 'arm64' ]; then DMG_URL="$(echo "$URLS" | grep -i arm64 | head -1)"
else DMG_URL="$(echo "$URLS" | grep -iv arm64 | head -1)"; fi
[ -n "${DMG_URL:-}" ] || { echo "v poslední release není .dmg pro $ARCH"; exit 1; }
DMG="$(mktemp -d)/AppFactoryWorker.dmg"
echo "   stahuji $(basename "$DMG_URL")"
curl -fL --progress-bar -o "$DMG" "$DMG_URL"
MNT="$(mktemp -d)"
hdiutil attach -nobrowse -quiet -mountpoint "$MNT" "$DMG"
rm -rf /Applications/AppFactoryWorker.app
cp -R "$MNT"/*.app /Applications/
hdiutil detach -quiet "$MNT"
open -a AppFactoryWorker
ok 'nainstalováno do /Applications a spuštěno'

cat <<'EOF'

== Hotovo. Ručně zbývá:
   ve Factory (https://appfactory.indracorp.cz) Workers -> + PŘIPOJIT WORKER
   a vydaný token vložit do appky (zobrazí se jen jednou)
EOF

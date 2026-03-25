#!/bin/bash
# Freelancer repo setup — installs git hooks for security
# Run once after cloning the repo

set -e

HOOKS_DIR=".git/hooks"

echo "Installing git hooks..."

# Pre-commit hook — blocks Tier 1 dangerous extensions
cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/bin/bash
# Block dangerous file extensions (Tier 1 — absolute block)
BLOCKED=$(git diff --cached --name-only | grep -iE '\.(scr|com|vbs|wsf|msi)$' || true)
if [ -n "$BLOCKED" ]; then
  echo "BLOCKED: Dangerous file extensions detected:"
  echo "$BLOCKED"
  echo "These file types are not allowed in this repository."
  exit 1
fi
HOOK
chmod +x "$HOOKS_DIR/pre-commit"

# Pre-push hook — warns about Tier 2 binaries, blocks push to main
cat > "$HOOKS_DIR/pre-push" << 'HOOK'
#!/bin/bash
# Block direct push to main
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "main" ]; then
  echo "BLOCKED: Direct push to main is not allowed."
  echo "Create a feature branch and open a pull request."
  exit 1
fi

# Warn about Tier 2 binary files
BINARIES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -iE '\.(exe|bat|cmd|ps1|dll|so|jar|bin)$' || true)
if [ -n "$BINARIES" ]; then
  echo "WARNING: Binary/executable files detected:"
  echo "$BINARIES"
  echo "These will be reviewed by the security check."
fi
HOOK
chmod +x "$HOOKS_DIR/pre-push"

echo "Git hooks installed successfully."
echo "  - pre-commit: blocks .scr .com .vbs .wsf .msi"
echo "  - pre-push: blocks push to main, warns about binaries"

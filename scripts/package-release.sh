#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATIC_DIR="$PROJECT_ROOT/TROVAT1O-Static-Preview-Pages"
FINAL_DIR="$PROJECT_ROOT/TROVAT1O-Local-Final-Preview"
DEPLOY_DIR="$PROJECT_ROOT/TROVAT1O-Cloudflare-Deploy"

WEB_FILES=(index.html index-v2.html config.js release.json sw.js site.webmanifest robots.txt _headers privacy.html cookie.html termini.html politiche.html)
DOC_FILES=(README.md DEPLOY-READINESS.md SECURITY.md BRAND-GUIDE.md UX-ITERATION-V2.md ADMIN-SETUP.md BILLING-SETUP.md RETENTION-SETUP.md ACCOUNT-LIFECYCLE.md ERASURE-REQUESTS.md PUSH-SETUP.md WRITE-QUOTAS.md UX-CHECKPOINT.md V1-STATUS.md CHANGELOG.md AUDIT-PREDEPLOY.md RELEASES.md)
DEPLOY_FILES=(README.md package.json package-lock.json wrangler.jsonc)

mkdir -p "$STATIC_DIR/assets/brand" "$DEPLOY_DIR/public/assets/brand" "$FINAL_DIR/assets" "$FINAL_DIR/TROVAT1O-Cloudflare-Deploy/public"

for file in "${WEB_FILES[@]}"; do
  cp "$PROJECT_ROOT/$file" "$STATIC_DIR/$file"
  cp "$PROJECT_ROOT/$file" "$DEPLOY_DIR/public/$file"
  cp "$PROJECT_ROOT/$file" "$FINAL_DIR/$file"
done

for file in "${DOC_FILES[@]}"; do
  cp "$PROJECT_ROOT/$file" "$FINAL_DIR/$file"
done

cp "$PROJECT_ROOT/README.md" "$STATIC_DIR/README.md"
cp "$PROJECT_ROOT/README.md" "$FINAL_DIR/README.md"
mkdir -p "$FINAL_DIR/TROVAT1O-Static-Preview-Pages"
cp "$STATIC_DIR/PREVIEW-ONLY.txt" "$FINAL_DIR/TROVAT1O-Static-Preview-Pages/PREVIEW-ONLY.txt"
cp "$PROJECT_ROOT/TROVAt10-logo.png" "$STATIC_DIR/TROVAt10-logo.png"
cp "$PROJECT_ROOT/TROVAt10-logo.png" "$FINAL_DIR/TROVAt10-logo.png"
cp "$PROJECT_ROOT/TROVAT1O-Cloudflare-Deploy/README.md" "$FINAL_DIR/TROVAT1O-Cloudflare-Deploy-README.md"
cp "$PROJECT_ROOT/config.example.js" "$FINAL_DIR/config.example.js"
for file in "${DEPLOY_FILES[@]}"; do
  cp "$DEPLOY_DIR/$file" "$FINAL_DIR/TROVAT1O-Cloudflare-Deploy/$file"
done

cp -R "$PROJECT_ROOT/assets/brand/." "$STATIC_DIR/assets/brand/"
cp -R "$PROJECT_ROOT/assets/brand/." "$DEPLOY_DIR/public/assets/brand/"
cp -R "$PROJECT_ROOT/assets/." "$FINAL_DIR/assets/"
cp -R "$PROJECT_ROOT/supabase" "$FINAL_DIR/"
cp -R "$PROJECT_ROOT/tests" "$FINAL_DIR/"
cp -R "$PROJECT_ROOT/scripts" "$FINAL_DIR/"
cp "$PROJECT_ROOT/.gitignore" "$FINAL_DIR/.gitignore"
if [ -d "$PROJECT_ROOT/.github" ]; then
  cp -R "$PROJECT_ROOT/.github" "$FINAL_DIR/"
fi
cp -R "$DEPLOY_DIR/public/." "$FINAL_DIR/TROVAT1O-Cloudflare-Deploy/public/"
if [ -d "$PROJECT_ROOT/output/pdf" ]; then
  mkdir -p "$FINAL_DIR/output/pdf"
  cp -R "$PROJECT_ROOT/output/pdf/." "$FINAL_DIR/output/pdf/"
fi

# Archive integrity alone cannot detect stale copies. Compare every entry point,
# configuration and policy page with the source before creating release files.
for file in "${WEB_FILES[@]}"; do
  cmp "$PROJECT_ROOT/$file" "$STATIC_DIR/$file"
  cmp "$PROJECT_ROOT/$file" "$DEPLOY_DIR/public/$file"
  cmp "$PROJECT_ROOT/$file" "$FINAL_DIR/$file"
  cmp "$PROJECT_ROOT/$file" "$FINAL_DIR/TROVAT1O-Cloudflare-Deploy/public/$file"
done
for file in "${DEPLOY_FILES[@]}"; do
  cmp "$DEPLOY_DIR/$file" "$FINAL_DIR/TROVAT1O-Cloudflare-Deploy/$file"
done
cmp "$PROJECT_ROOT/supabase/schema.sql" "$FINAL_DIR/supabase/schema.sql"
cmp "$PROJECT_ROOT/supabase/notifications.sql" "$FINAL_DIR/supabase/notifications.sql"
STATIC_ZIP_TMP="$PROJECT_ROOT/TROVAT1O-Static-Preview-Pages.tmp.zip"
FINAL_ZIP_TMP="$PROJECT_ROOT/TROVAT1O-Local-Final-Preview.tmp.zip"
rm -f "$STATIC_ZIP_TMP" "$FINAL_ZIP_TMP"
(cd "$PROJECT_ROOT" && zip -qr "$STATIC_ZIP_TMP" TROVAT1O-Static-Preview-Pages -x '*/.DS_Store' '*/node_modules/*' '*/.wrangler/*' '*/.git/*' '*/.env' '*/.env.*' '*/.dev.vars' '*/.dev.vars.*' '*/.npmrc' '*.log')
(cd "$PROJECT_ROOT" && zip -qr "$FINAL_ZIP_TMP" TROVAT1O-Local-Final-Preview -x '*/.DS_Store' '*/node_modules/*' '*/.wrangler/*' '*/.git/*' '*/.env' '*/.env.*' '*/.dev.vars' '*/.dev.vars.*' '*/.npmrc' '*.log')
mv -f "$STATIC_ZIP_TMP" "$PROJECT_ROOT/TROVAT1O-Static-Preview-Pages.zip"
mv -f "$FINAL_ZIP_TMP" "$PROJECT_ROOT/TROVAT1O-Local-Final-Preview.zip"
(cd "$DEPLOY_DIR" && tar -czf trovato-static-assets.tar.gz public)

printf 'Preview, handoff package, and Cloudflare assets synchronized.\n'

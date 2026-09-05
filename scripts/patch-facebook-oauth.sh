#!/bin/sh
# Patches Postiz OAuth for Meta API changes:
# 1. Remove versioned dialog URL (PLATFORM_INVALID_APP_ID on new Meta apps)
# 2. Remove deprecated read_insights scope from Facebook (issue #1346)
#
# NOTE: instagram.provider.js uses facebook.com/dialog/oauth (Facebook Login).
# It must keep instagram_basic/* scopes, NOT instagram_business_* (those are for
# instagram.com/oauth/authorize via instagram.standalone.provider.js only).
set -eu

FACEBOOK_FILES="
/app/apps/backend/dist/libraries/nestjs-libraries/src/integrations/social/facebook.provider.js
/app/apps/orchestrator/dist/libraries/nestjs-libraries/src/integrations/social/facebook.provider.js
"

INSTAGRAM_FB_FILES="
/app/apps/backend/dist/libraries/nestjs-libraries/src/integrations/social/instagram.provider.js
/app/apps/orchestrator/dist/libraries/nestjs-libraries/src/integrations/social/instagram.provider.js
"

for f in $FACEBOOK_FILES $INSTAGRAM_FB_FILES; do
  if [ ! -f "$f" ]; then
    continue
  fi
  sed -i 's|www.facebook.com/v20.0/dialog/oauth|www.facebook.com/dialog/oauth|g' "$f"
done

for f in $FACEBOOK_FILES; do
  if [ ! -f "$f" ]; then
    continue
  fi
  sed -i "/'read_insights',/d" "$f"
done

# Undo wrong instagram_business_* patch if image was previously patched
for f in $INSTAGRAM_FB_FILES; do
  if [ ! -f "$f" ]; then
    continue
  fi
  sed -i "s/'instagram_business_basic'/'instagram_basic'/" "$f"
  sed -i "s/'instagram_business_content_publish'/'instagram_content_publish'/" "$f"
  sed -i "s/'instagram_business_manage_comments'/'instagram_manage_comments'/" "$f"
  sed -i "s/'instagram_business_manage_insights'/'instagram_manage_insights'/" "$f"
  sed -i "/'instagram_business_manage_messages',/d" "$f"
done

echo "Postiz OAuth patches applied."

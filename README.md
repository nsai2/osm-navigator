# Flutter OSM Navigator (APK via GitHub Actions)

This repo builds an Android APK for a GNSS navigator using OpenStreetMap + MapLibre (maplibre_gl ^0.22.0),
Nominatim search, and OSRM routing.

## Quick start
1) Create a new GitHub repo and upload all files from this ZIP (keep folders). Commit to your DEFAULT branch.
2) Open the **Actions** tab. If you see a banner, click **Enable workflows**.
3) Click **Android APK** → **Run workflow**.
4) After it finishes, download the **app-release-apk** artifact and install it.

### Troubleshooting
- If the workflow doesn't show, edit README and commit — this triggers detection.
- If **Run workflow** is missing, check **Settings → Actions → General** and allow actions.

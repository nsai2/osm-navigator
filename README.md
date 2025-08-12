# Flutter OSM Navigator — APK via GitHub Actions (Fixed)

This builds an Android APK using OSM + MapLibre (maplibre_gl ^0.22.0), Nominatim, and OSRM.

## Steps
1) New GitHub repo → upload these files to DEFAULT branch.
2) Actions → **Android APK** → **Run workflow** (or push to trigger).
3) Download **app-release-apk** artifact.

## Fixes
- Flutter **v2 embedding** manifest
- **NDK pinned** to 28.1.13356709 (workflow patches build.gradle(.kts))
- MapLibre 0.22 API updates

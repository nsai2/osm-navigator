# Flutter OSM Navigator — APK via GitHub Actions

GNSS navigation using OpenStreetMap + MapLibre (`maplibre_gl ^0.22.0`), Nominatim search, OSRM routing.

## Build APK in GitHub (no Android Studio)
1) Create a new GitHub repo → upload ALL files from this ZIP (keep folder structure) to your DEFAULT branch.
2) Open **Actions** → you should see **Android APK**.
3) Click **Run workflow** (select default branch) — or just push a commit to trigger.
4) After it finishes, download the **app-release-apk** artifact and install it on your phone.

## Why this works (fixes included)
- **Flutter v2 embedding** (manifest includes `flutterEmbedding=2`).
- **NDK pinned** to **28.1.13356709** to satisfy `maplibre_gl` and `geolocator_android`.
- **MapLibre 0.22 API**: corrected imports, removed deprecated options.

## Notes
- Public OSRM/Nominatim endpoints are for testing; heavy use may rate-limit.
- Map data © OpenStreetMap contributors.

# Flutter OSM Navigator (APK via GitHub Actions)

This repo builds an **Android APK** using **OpenStreetMap + MapLibre** for maps,
**Nominatim** for search, and **OSRM** for routing. It runs entirely in GitHub Actions —
no Android Studio required.

## What you get
- OSM raster map via MapLibre
- GNSS live position + heading
- Search places (Nominatim)
- Driving route (OSRM demo server)
- Polyline, distance, ETA
- Simple navigation with basic auto‑reroute

## One‑time steps
1. Create a new GitHub repository and upload ALL files from this ZIP (keep paths).
2. Go to **Actions** → enable workflows.
3. Run the workflow **Android APK** (or push to `main`).

## Download the APK
- After the run finishes, open the run → **Artifacts** → download **app-release-apk**.
- Sideload on your device (allow Unknown Sources).

## How the workflow works
1. `flutter create . --platforms=android` to generate the Android/Gradle scaffold.
2. Copy `app_src/*` into place (lib, AndroidManifest, pubspec).
3. `flutter pub get` and `flutter build apk --release`.
4. Upload the resulting APK as an artifact.

## Notes
- Public demo services may rate-limit. For production, use your own providers (e.g., hosted tiles and routing).
- Map data © OpenStreetMap contributors. Geocoding by Nominatim. Routing by OSRM.

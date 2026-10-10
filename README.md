# Frame Finder: face detection and virtual eyeglass try-on

A Flutter app that detects your face on the phone and overlays eyeglass frames
on your eyes, either live from the camera or on a photo. A FastAPI backend
serves the frame catalogue from Neon PostgreSQL.

```
┌────────────── Phone (Flutter) ──────────────┐        ┌──── FastAPI ────┐      ┌── Neon ──┐
│ camera / gallery                            │  HTTP  │ GET /health      │ TLS  │ glasses  │
│   └─► ML Kit face + eye landmarks (on-device)│◄──────►│ GET /glasses     │◄────►│ table    │
│        └─► 1€ smoothing ─► 2D overlay       │  JSON  │ GET /glasses/{id}│      └──────────┘
│ Riverpod state · Dio · local favorites      │        │ /static (PNGs)   │
└──────────────────────────────────────────────┘        └──────────────────┘
```

* Face images never leave the device. The backend only serves catalogue data and images.
* The app never connects to PostgreSQL. Only the backend holds `DATABASE_URL`.
* If the backend can't be reached, the app falls back to a bundled offline copy
  of the same catalogue, so the try-on still works.

---

## 1. Concepts: what this app does and doesn't do

| Term | What it is | In this app |
|---|---|---|
| **Face detection** | Finding where a face is in an image, plus landmark points (eyes, nose, mouth) and head angles. It does not identify the person. | ✅ Google ML Kit Face Detection, on-device. |
| **Face-shape classification** | Labelling a face as oval / round / square / heart, etc. This is a separate prediction task that needs its own trained and validated model. | ❌ Not included. Landmark-based rules would only be rough hints, so no recommendations are made and no accuracy is claimed. |
| **Virtual try-on** | Rendering a product on the user's face. | ✅ A **2D geometric overlay**: a transparent PNG is scaled, rotated and positioned from the eye landmarks. It is not a trained AI model, and it shows roughly how a frame looks, not a measurement of fit. |

### How the 2D fit is computed
1. ML Kit returns the centres of the left and right eye, the bounding box and the
   Euler angles (yaw Y, pitch X, roll Z) in **upright image coordinates**.
2. Scene checks: exactly one face, wide enough (≥ 12 % of the frame), both eyes
   found, |yaw| ≤ 28°, |pitch| ≤ 25°, |roll| ≤ 35°. Otherwise the overlay is
   **hidden** and a guidance message is shown.
3. The eye midpoint, eye distance and the angle of the line through the eyes are
   smoothed with a **1€ filter** (adaptive low-pass: strong smoothing when still,
   low lag when moving). Brief drop-outs (≤ 250 ms, e.g. a blink) keep the last pose.
4. Image → screen mapping (`CoordinateMapper`): rotation-corrected size, mirroring
   for the front camera, uniform scale + centred crop (`cover`) for the live
   preview, or letterbox (`contain`) for photos.
5. Placement (`GlassesPlacement`): `width = eyeDistance / eye_span_ratio × scale`,
   rotated by the eye-line angle and anchored at `(anchor_x, anchor_y)` of the PNG.
   Manual size/offset adjustments are relative to the eye distance.

### Platform handling
* **Android:** NV21 frames are in sensor orientation. The rotation passed to ML
  Kit is `sensor ± device orientation` (as in the official ML Kit example), so
  90°/270° swaps width and height. The front-camera preview is mirrored but the
  frames are not, so x is flipped.
* **iOS:** BGRA frames are delivered upright (and mirrored for the front camera),
  matching the preview, so no swap or flip is needed.
* The UI and capture orientation are locked to portrait.
* Gallery photos and captures are re-encoded with EXIF orientation applied
  (`image_normalizer.dart`), so detection, display and the saved image all use
  the same pixels.

### Limitations of 2D try-on (by design)
* **Side views:** a flat front-view image can't show the temples or the frame's
  depth, so the overlay hides beyond about 28° of head turn.
* **No occlusion:** hair, hands or your own glasses are never drawn in front of
  the frame.
* **Scale:** size comes from the eye distance and an average pupil-to-frame-width
  ratio, not your real face width. Use **Adjust fit** to correct it.
* **Lighting and reflections** are not simulated. Lens tint is a fixed transparency.
* Landmark jitter is reduced, not eliminated. Accuracy drops in poor light, with
  motion blur, or when the eyes are partly covered.
* **Next step:** realistic 3D try-on would use a face mesh (for example MediaPipe
  Face Landmarker), 3D frame models, head-pose solving and depth-based occlusion.

---

## 2. Project structure

```
backend/
  app/
    main.py              FastAPI app, /health, CORS, /static mount
    config.py            settings from env / backend/.env (DATABASE_URL, ASSET_BASE_URL)
    database.py          SQLAlchemy engine (psycopg 3, Neon SSL kept, pool_pre_ping)
    models.py            Glasses ORM model
    schemas.py           response models incl. FitMetadata
    assets.py            relative path → absolute URL resolution
    routers/glasses.py   GET /glasses, GET /glasses/{id}
  alembic/               migrations (version table: alembic_version_eyewear)
  scripts/
    inspect_db.py        read-only DB inspection (run before migrating)
    generate_glasses_assets.py   draws the 10 demo frames + fit metadata
    seed_glasses.py      idempotent, non-destructive insert of the demo catalogue
  static/glasses/        demo PNGs + catalogue.json
  tests/                 pytest (SQLite in-memory, never touches Neon)
mobile/
  lib/
    main.dart, app.dart  bootstrap, theme, bottom-nav shell
    core/                api_config (base URL), theme
    models/              Glasses, FitMetadata, FitAdjustment
    services/            Dio API client, repository + offline fallback, gallery, photo normaliser
    face_tracking/       ML Kit tracker, pose estimator, 1€ filter, coordinate mapping, placement
    providers/           Riverpod providers (catalogue, favorites, selection, API URL…)
    screens/             Home, Catalogue, Detail, Try-On, Favorites, Settings
    widgets/             overlay painters, frame selector, adjust panel, cards…
  assets/glasses/        bundled copy of the demo catalogue (offline mode)
  test/                  unit tests: coordinate transforms, placement, smoothing, API
  tool/configure_platforms.py   adds Android/iOS permissions after `flutter create`
```

---

## 3. Backend setup (FastAPI + Neon)

Requirements: Python 3.11+ (tested with 3.12.8).

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate     macOS/Linux: source .venv/bin/activate
pip install -r requirements-dev.txt

cp .env.example .env        # Windows: copy .env.example .env
# edit .env and paste your Neon connection string into DATABASE_URL
```

**Neon connection string:** Neon Console → your project → **Connect** → copy the
`postgresql://…?sslmode=require&channel_binding=require` URL. Keep the query
parameters. The backend switches the driver to **psycopg 3** and passes
`sslmode`/`channel_binding` to libpq unchanged, so TLS is enforced.
`backend/.env` is git-ignored. Never commit it or paste it into the app.

```bash
python -m scripts.inspect_db          # read-only: lists existing tables, confirms TLS
alembic upgrade head                  # creates the `glasses` table (additive only)
python -m scripts.seed_glasses        # inserts the 10 demo frames (skips existing names)
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

* Open http://localhost:8000/docs for the interactive API docs.
* `--host 0.0.0.0` is needed so a phone on your Wi-Fi can reach it.
* Run tests with `pytest`. They use SQLite in memory, never Neon.

**Safety measures in the migration:**
* Alembic uses its own version table (`alembic_version_eyewear`), so it can't
  collide with another project's migration history in the same database.
* Autogenerate is configured to ignore tables it doesn't own, so it never
  proposes dropping them.
* The seed script never deletes. Pass `--update` to overwrite rows with the
  same name.

### Object storage
The table stores image URLs. The demo rows hold relative paths
(`/static/glasses/x.png`), which the API turns into absolute URLs using the
host the client called, so emulators and phones both work. To use S3, R2 or GCS:

1. Upload `backend/static/glasses/*.png` to a public bucket.
2. Run `python -m scripts.seed_glasses --update --asset-base-url https://<bucket-url>`
   to store absolute URLs, **or** set `ASSET_BASE_URL=https://<bucket-url>` in
   `.env` to rewrite the relative paths at request time.

### API
| Method | Path | Response |
|---|---|---|
| GET | `/health` | `{"status":"ok","database":"ok"}`, or HTTP 503 `{"status":"degraded","database":"unavailable"}` |
| GET | `/glasses?category=&limit=&offset=` | `{"items":[Glasses…],"total":n}` |
| GET | `/glasses/{id}` | `Glasses`, or 404 `{"detail":"Glasses not found"}` |

`Glasses` fields: `id, name, category, description, price, currency,
catalogue_image_url, transparent_overlay_url, fit_metadata, created_at`.
`fit_metadata` contains `image_width, image_height, anchor_x, anchor_y,
eye_span_ratio, default_scale` plus informational `left_lens_center`,
`right_lens_center` and `frame_bounds` (all normalised 0–1).

---

## 4. Demo eyeglass assets: source and generation method

The 10 frames are **original artwork drawn in code** by
`backend/scripts/generate_glasses_assets.py` (Pillow, 4× supersampled for
anti-aliasing). They are not downloaded product photos. Images from a web
search are usually copyrighted and are not front-on transparent cut-outs with
known lens positions, which try-on needs.

Because the script draws each frame, it knows the exact lens and bridge
geometry and writes the fitting metadata from it:

* `eye_span_ratio = 0.45 × frame_width / png_width`. The 0.45 is the ratio of an
  average adult pupil distance (~63 mm) to an average frame width (~140 mm).
* `anchor_y` = where the pupils sit vertically (aviators sit a bit higher in the lens).

| Frame | Category | Demo price |
|---|---|---|
| Aviator Classic | Aviator | $129 |
| Wayfarer Black | Wayfarer | $99 |
| Round Wire Gold | Round | $89 |
| Cat-Eye Tortoise | Cat-Eye | $115 |
| Browline Classic | Browline | $109 |
| Slim Rectangle | Rectangle | $79 |
| Oversized Square Crystal | Square | $119 |
| Rimless Titanium | Rimless | $149 |
| Hexagon Silver | Geometric | $95 |
| Semi-Rimless Navy | Semi-Rimless | $105 |

Prices are illustrative and the names are generic style names, not brands. To
regenerate the assets and copy them into the app:

```bash
cd backend
python -m scripts.generate_glasses_assets --flutter-assets ../mobile/assets/glasses
python -m scripts.seed_glasses --update
```

To add real frames, use front-view PNGs with a transparent background, centred,
with level lenses, and set `eye_span_ratio`/`anchor_y` for each.

---

## 5. Flutter app setup

**Requirements:** Flutter **≥ 3.44** (Dart ≥ 3.12); built against stable 3.47.
Android Studio or the Android SDK, a physical Android phone running **Android 7.0
(API 24)+**. For iOS: Xcode 15.3+, iOS **15.5+** (ML Kit requirement), 64-bit devices.

| Package | Version | Purpose |
|---|---|---|
| google_mlkit_face_detection | ^0.15.1 | on-device face and eye landmarks (Android/iOS only) |
| camera | ^0.12.1 | preview and frame stream (CameraX on Android) |
| image_picker | ^1.2.4 | gallery photos |
| gal | ^2.3.3 | save to gallery with permission handling |
| flutter_riverpod | ^3.4.3 | state management |
| dio | ^5.11.1 | HTTP |
| shared_preferences | ^2.5.6 | favorites and API URL |
| image | ^4.10.2 | EXIF orientation and resizing of photos |
| path_provider | ^2.1.6 | temp files |

The repository contains `lib/`, `test/`, `assets/` and `pubspec.yaml`. The
native `android/` and `ios/` folders are generated by Flutter, then patched with
the required permissions:

```bash
cd mobile
flutter create . --project-name glasses_tryon --org com.example --platforms android,ios
python tool/configure_platforms.py     # adds permissions, minSdk 24, iOS 15.5, plist keys
flutter pub get
flutter test                            # unit tests
```

`configure_platforms.py` is idempotent. It adds:
* **Android:** `CAMERA`, `INTERNET`, `WRITE_EXTERNAL_STORAGE` (API ≤ 29 only,
  for saving; uses `tools:replace` because the camera plugin declares it with
  max 28), `requestLegacyExternalStorage`, cleartext HTTP **in debug/profile
  builds only** (for `http://<LAN-IP>:8000`), and `minSdk ≥ 24`.
* **iOS:** camera, microphone (required by the camera plugin, not used) and
  photo-library usage strings, `NSAllowsLocalNetworking`, and the 15.5
  deployment target. For iOS, run the script again after the first
  `flutter build ios`, so it can also patch the generated `Podfile`.

---

## 6. Run on a real Android phone

1. **Phone:** Settings → About phone → tap *Build number* 7 times. Then
   Developer options → enable **USB debugging**. Connect by USB and accept the
   "Allow USB debugging" prompt.
2. `flutter devices` should list the phone.
3. **Same Wi-Fi:** connect the phone and the computer to the same network. Find
   the computer's IP address (`ipconfig` on Windows, the IPv4 Address of the
   Wi-Fi adapter, e.g. `192.168.1.20`).
4. **Start the backend:** `uvicorn app.main:app --host 0.0.0.0 --port 8000`. On
   Windows, allow Python through the firewall on *Private* networks when
   prompted, or open TCP port 8000. Test from the phone's browser:
   `http://192.168.1.20:8000/health`.
5. **Run the app:**
   ```bash
   cd mobile
   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
   ```
   You can also change the URL later in the app: **Home → ⚙ Settings → Test
   connection → Save**. The Android emulator default is `http://10.0.2.2:8000`.
6. Open **Try-On**, allow camera access, and face the phone.

Release builds block plain `http://`. Deploy the API behind HTTPS (for example
Render, Fly.io or Railway) and pass that URL instead.

### Release APK to share with other people

```bash
cd mobile
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk
```

* A release build made **without** `--dart-define=API_BASE_URL` has no server.
  It uses the 10 frames bundled in the app and shows no server warnings, so it
  works on any Android phone (7.0+) without your PC. Face detection always runs
  on the phone.
* To serve the catalogue from your backend instead, deploy it over **HTTPS**
  and build with `--dart-define=API_BASE_URL=https://your-api.example.com`.
* **Signing:** `android/upload-keystore.jks` + `android/key.properties`
  (git-ignored) sign the release. **Back both up somewhere safe.** Future
  updates must be signed with the same key to install over the old version.
  Without `key.properties` the build falls back to debug signing.
* **Installing:** recipients open the APK and allow "Install unknown apps" for
  the app they opened it from (Files, WhatsApp, Drive…). Play Protect may warn
  about an app from an unknown developer; that's expected for sideloaded APKs.
* **App icon:** `python tool/generate_branding.py && dart run flutter_launcher_icons`
  regenerates the logo (original artwork drawn in code) and launcher icons.

---

## 7. Status: what works, what was tested, what's left

### Verified in this environment
* **Neon database:** inspected first (the `public` schema was empty), then
  `alembic upgrade head` created `glasses`, and the seed script inserted the 10
  frames. TLS to Neon was confirmed (`ssl_in_use = True`). `alembic check`
  reports the models and migration in sync.
* **Backend:** 19 pytest tests pass: health, health failure without leaking
  details, list, category filter, pagination, get by id, 404, 422, URL
  resolution, static files, URL normalisation keeping SSL params, and catalogue
  consistency. The live server was also run against Neon, and `/health`,
  `/glasses`, `/glasses/999` (404) and a static PNG returned the expected
  responses.
* **Assets:** the generator was run and the outputs were checked visually.
* **Platform script:** run twice against the official `flutter create`
  templates. The patched manifests and Info.plist parse as valid XML and plist,
  and the second run changes nothing.

### Not verified here
* **The Flutter app was not compiled or run, and `flutter test` was not run.**
  No Flutter SDK was installed in this environment. The Dart code was written
  against the current documented APIs of each package version and reviewed by
  hand, and the expected values in the Dart tests were checked by hand. Run
  `flutter analyze` and `flutter test` first; small API-drift fixes may be
  needed.
* On-device behaviour (overlay alignment, mirroring, smoothing feel,
  permissions, gallery saving) needs testing on a real phone. iOS frame
  orientation follows the official ML Kit example but has not been tried on a
  device.

### Known limitations / next steps
* 2D overlay limitations as listed in section 1 (side views, occlusion, scale).
* Favorites are local to the device (no accounts).
* Captured or picked photos are kept only in the app's temp folder while shown,
  and deleted afterwards. Only images you explicitly **Save** go to the gallery.
* The pose limits and smoothing parameters (`pose_estimator.dart`) are
  reasonable defaults, not tuned on a dataset.
* Future work: 3D try-on (face mesh + glTF frames + occlusion), object-storage
  upload tooling, an admin API for adding frames.

## 8. Security notes
* `DATABASE_URL` lives only in `backend/.env` (git-ignored). The engine hides
  parameters in errors, `/health` never returns error details, and scripts print
  only the host and database name.
* If a connection string has been shared anywhere (chat, screenshots,
  tickets), **reset the database password** in Neon (Roles → Reset password)
  and update `backend/.env`.

# RhythmSync

RhythmSync is a responsive music community built around audio and images: musicians publish audio tracks with artwork, listeners and musicians share image posts, and anyone with a registered account can upload a raw freestyle recording. Members can like and comment on tracks, posts, and freestyles. The For You feed ranks image posts using likes, comments, and views.

The front end is `mine.html`. The separate Express API in `server.js` validates account ownership, compresses audio with FFmpeg, stores optimized images and audio in Supabase Storage, and writes metadata to Supabase. It does not accept or serve video uploads.

The restricted `admin.html` security console shows recent request, authentication, rate-limit, and server-error events live. It is protected by Supabase authentication plus an explicit `ADMIN_USER_IDS` allowlist. It never displays access tokens, passwords, or raw IP addresses. Security events are persisted as rotating JSONL files under `logs/`; use centralized immutable logging and alerting for production or multiple server instances.

## Requirements

- Node.js 20 or newer
- npm
- FFmpeg and FFprobe available on `PATH` (or use the included deployment image)
- A Supabase project with `supabase-setup.sql` applied

## Install FFmpeg locally

Windows PowerShell (using winget):

```powershell
winget install Gyan.FFmpeg.Shared
```

Reopen the terminal, then check `ffmpeg -version` and `ffprobe -version`. Alternatively, add the FFmpeg `bin` directory to `PATH` or set `FFMPEG_PATH` and `FFPROBE_PATH` in `.env`. On macOS use `brew install ffmpeg`; on Debian/Ubuntu use `sudo apt update && sudo apt install ffmpeg`.

## Deploy with FFmpeg included

The repository includes a `Dockerfile` that installs FFmpeg and FFprobe inside the deployment image. No Windows paths or local FFmpeg installation are required in production:

```powershell
docker build -t rhythmsync .
docker run --env-file .env -p 3000:3000 rhythmsync
```

Set `WEB_ORIGIN` to the public URL of the deployed web app (for example `https://music.example.com`) and keep `SUPABASE_SERVICE_ROLE_KEY` server-only. The container listens on port `3000` unless `PORT` is set by the hosting provider. The `/api/health` endpoint can be used as the deployment health check.

## Configure Supabase

1. Run `supabase-setup.sql` in the Supabase SQL Editor. It creates the image-post and freestyle tables and adds profile/contact fields, engagement functions, and audio/image-only Storage MIME types.
2. In Supabase Auth settings, enable anonymous sign-ins so visitors can like and comment without an account. Uploading requires a registered account; publishing music tracks additionally requires the musician role.
3. Enable the Google provider in Supabase Auth, configure the Google OAuth client ID and secret, and add your Supabase Auth callback URL (`https://<project-ref>.supabase.co/auth/v1/callback`) in Google Cloud. Add your deployed site URL and redirect URL in Supabase Auth URL configuration.
4. Configure `SUPABASE_URL` and a **server-only** `SUPABASE_SERVICE_ROLE_KEY` in `.env`. Never put the service-role key in the browser or a public repository. `mine.html` uses only the project's public/publishable key.
5. The `media` bucket is public for playback and image display. Its default 100 MiB object cap matches the API's default processed-audio limit.
6. To enable GA4, replace `G-XXXXXXXXXX` in `mine.html` with your Google Analytics 4 Measurement ID. Visitors are asked to opt in before the analytics script loads; they can later change their choice with **Privacy & analytics settings**.

The SQL setup intentionally preserves the legacy `clips` and `music_videos` tables and their existing records. RhythmSync no longer displays, queries, or accepts video content.

## Install and run

From the project directory:

```powershell
Copy-Item .env.example .env
npm install
```

Set these values in `.env`:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-server-only-service-role-key
PORT=3000
WEB_ORIGIN=http://localhost:3000
MAX_UPLOAD_MB=500
MAX_PROCESSED_MB=100
ADMIN_USER_IDS=comma-separated-supabase-user-uuids
AUDIT_HASH_SECRET=long-random-secret-for-hashing-network-identifiers
AUDIT_LOG_DIR=./logs
```

Start with `npm start` and visit `http://localhost:3000`. For development use `npm run dev`. Run `npm run check` to check the backend JavaScript syntax. Do not open the page as a `file://` URL when uploading; the app needs the same-origin API.

## Publishing

`POST /api/media/upload` accepts authenticated multipart uploads:

- `mediaType=track`: audio file in `media`, required image artwork in `cover`; musician account only.
- `mediaType=freestyle`: audio file in `media`; registered listener or musician account.
- `mediaType=post`: optimized JPEG, PNG, WebP, or AVIF image in `media`; registered listener or musician account.
- `mediaType=profile_image`: optimized image in `media`; registered account.

The browser downsizes and converts images to WebP before upload. Audio is transcoded to AAC/M4A at 192 kbps. Conversion is lossy; resulting size depends on the source. Uploads larger than the configured storage limit are rejected. Local originals and converted audio are removed after success or failure.

Tracks must be between **30 seconds and 6 minutes**, inclusive. Freestyles must be between **10 and 60 seconds**, inclusive. The browser checks the selected file and the server independently checks both the source and converted audio with FFprobe. Invalid durations are rejected with a clear “too short” or “too long” error.

The dashboard supports profile image, display name, bio, and optional public contact email/phone. Users can remove their own uploaded tracks, image posts, and freestyles from the dashboard.

## Security console and operational controls

1. Create a dedicated administrator account in Supabase Auth.
2. Copy its user UUID into `ADMIN_USER_IDS`. Do not authorize an email or a role supplied by the browser.
3. Set a strong random `AUDIT_HASH_SECRET`, keep it server-only, and persist the `logs/` directory only on protected storage.
4. Open `/admin.html` after signing in. The console uses a live server-sent event stream and supports a manual refresh.
5. Put the service behind HTTPS, a managed WAF/reverse proxy, network-level firewall rules, backups, centralized log retention, and alerting. The application rate limiter is an application control, not a complete firewall.

The server applies Helmet headers, strict CORS, JSON size limits, upload limits, global request limiting, upload-specific limiting, authenticated owner checks, role checks, temporary-file cleanup, and cloud cleanup on failed uploads. No software can guarantee prevention of every attack; keep dependencies patched and review logs regularly.

## Terms and privacy

`terms.html` is a general product template covering content rights, prohibited conduct, moderation, downloads, privacy, and service availability. It is not legal advice and cannot guarantee protection from claims. Have qualified counsel adapt it to your jurisdiction, retention obligations, age requirements, intellectual-property process, and support contact details before launch.

Email/password and Google OAuth are available on the public sign-in form and the administrator console. Google-created public accounts begin as listeners; the role selection remains available for email/password registration so musician publishing access is not granted unexpectedly by an OAuth callback.

## Comments and analytics

Visitors may like and comment on tracks, image posts, and freestyles without creating a registered account. The comment form checks for abusive/profane terms, and a Supabase trigger enforces the same normalized English-language blocklist on database inserts. This is a practical profanity filter, not comprehensive multilingual moderation; review reports and extend the word list to fit your community.

After you set a GA4 Measurement ID, users can opt in or decline. Opted-in analytics records page views and broad events such as audio plays, likes, comment activity, searches, shares, follows, uploads, downloads, and profile/auth actions. Event data excludes emails, comment text, search queries, account IDs, and content IDs. Google Analytics only receives events after the visitor grants analytics consent.

Signed-in users can follow artists and like tracks, posts, and freestyles. Their dashboard shows saved activity and followed artists, while the feed gives followed creators and previously liked content a ranking boost. Anonymous likes remain available, but personalization requires a registered account.

## Security

- Keep the service-role key in the server's `.env` only; rotate any key previously shared in chat or committed.
- Upload and delete endpoints verify the Supabase access token and profile ownership.
- CORS is restricted to `WEB_ORIGIN`. Use HTTPS for deployed sites.
- Contact details are optional and visible to anyone who can view the profile; only provide details intended for public display.

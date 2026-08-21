# TG Focus

A simple Flutter Android app that signs into your Telegram account and shows **only the groups you select** — with read, reply, and local notifications.

## Setup

1. Create an API app at [my.telegram.org](https://my.telegram.org) → **API development tools**.
2. Copy `.env.example` to `.env` and fill in:

```
TELEGRAM_API_ID=12345678
TELEGRAM_API_HASH=your_hash_here
```

3. **Linux desktop:** ensure `linux/libs/libtdjson.so` exists (prebuilt TDLib). If missing, download with:

```bash
./tool/fetch_linux_tdlib.sh
```

4. Run:

```bash
# Android
flutter run

# Linux
flutter run -d linux
```

## Usage

1. Sign in with phone number, Telegram code, and 2FA if enabled.
2. Pick the groups/channels you care about.
3. Read and reply from the home list.
4. New messages in followed groups raise a system notification while the app is running.

## Notes

- Uses TDLib via the `tdlib` Flutter plugin (Android `libtdjson.so`).
- Credentials in `.env` are gitignored — never commit them.
- Background delivery is best-effort while the process is alive; keep the app open or recent for reliable alerts in v1.

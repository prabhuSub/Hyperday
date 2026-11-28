# Hyperday push server

Runs on your Raspberry Pi and sends Live Activity updates at the exact start and end of each block, so the Lock Screen card switches on time even when the app is asleep.

The iPhone does all the planning: whenever your day changes, it sends the Pi the rest of today's card states with the time each one should appear. The Pi only sends them to Apple at those times.

## Install on the Pi

```bash
scp -r server your-pi:~/hyperday-server
ssh your-pi 'cd ~/hyperday-server && sudo ./install.sh'
```

`install.sh` creates a service user, a virtualenv in `/opt/hyperday-push`, the settings file `/etc/hyperday-push.env` (with a random app token), a systemd service on `127.0.0.1:8787`, and publishes it to your tailnet with `tailscale serve` (HTTPS, only your devices can reach it). Run it again to update.

## Turn on real pushes (needs the Apple Developer Program)

Until an APNs key is set, the server runs in **dry-run** mode: it accepts schedules and logs what it would send.

1. developer.apple.com › Certificates, IDs & Profiles › **Keys** › **+** › enable **Apple Push Notifications service (APNs)** › download `AuthKey_XXXXXXXXXX.p8` (you can download it only once).
2. Copy it to the Pi: `scp AuthKey_*.p8 your-pi:/tmp/ && ssh your-pi 'sudo install -o hyperday -m 600 /tmp/AuthKey_*.p8 /var/lib/hyperday-push/AuthKey.p8'`
3. In `/etc/hyperday-push.env` set `APNS_TEAM_ID` and `APNS_KEY_ID`, then `sudo systemctl restart hyperday-push`.
4. `curl https://your-pi.<your-tailnet>.ts.net/health` shows `"dry_run": false`.

`APNS_ENV=sandbox` is right for builds from `deploy.sh`. Use `production` for TestFlight or App Store builds.

## API

All `/v1` calls need `Authorization: Bearer <HYPERDAY_AUTH_TOKEN>`.

| Call | What |
|---|---|
| `GET /health` | status, version, dry-run |
| `POST /v1/schedule` | tokens + the rest of today's events `{at, kind: start/update/end, content_state, stale_date?, dismissal_date?, attributes?}`. Replaces unsent events for that device. |
| `POST /v1/tokens` | update the Live Activity token or the push-to-start token |
| `POST /v1/test` | send one update now |
| `GET /v1/status` | pending and recent sends |

Updates more than 10 minutes late (for example, the Pi was off) are skipped; "end" is always sent.

## Logs and tests

```bash
journalctl -u hyperday-push -f
cd server && pip install -r requirements.txt pytest && python -m pytest
```

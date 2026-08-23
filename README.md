# Dynamic Dashboard

Dynamic Dashboard is a standalone Tidbyt app intended to run as the only app
on a device. The clock is always present. Optional tiles appear when their
signal is active:

| Active items | Layout |
| --- | --- |
| 1 | One full-screen tile |
| 2 | Two 32x32 half-screen tiles |
| 3 | Two 32x16 quarter tiles and one 64x16 half tile |
| 4 | Four 32x16 quarter tiles |

The current item order is clock, Spotify, weather, then sports. The maximum is
four tiles.

## Current implementation

- Clock: implemented; uses the Tidbyt timezone (`$tz`) and a 24-hour digital
  display.
- Tiling: implemented in `layout.star`; deterministic for one through four
  active items.
- Weather: implemented for US National Weather Service locations. It adds a
  tile when one of the next six hourly periods has precipitation probability
  or a precipitation forecast.
- Sports: implemented with ESPN's public scoreboard endpoints for NFL, NBA,
  MLB, NHL, and MLS. It adds the first live game matching a configured team.
- Spotify playback: implemented against `/v1/me/player` when a valid bearer
  token is supplied.

All non-successful provider responses are intentionally fail-soft: the clock
remains visible. Provider results are cached with short TTLs so the app does
not fetch on every render.

## Explicit stubs and limitations

- Spotify OAuth, refresh-token storage, and automatic account/integration
  discovery are not implemented. For now, `spotify_access_token` is a
  temporary developer input and should not be treated as secure secret
  storage. The OAuth follow-up is marked `TODO(spotify-oauth)` in the app.
- Weather currently uses the US NWS API only and checks six hours. There is no
  international provider fallback, radar imagery, or multi-location support.
- Sports matching is simple abbreviation/name matching and shows only the
  first matching live event. There is no team picker, logos, game paging, or
  finished/upcoming game tile.
- There is no persisted stale-data store beyond Pixlet's HTTP cache. A
  provider outage therefore removes that provider's tile until a later
  successful fetch.

## Local verification

With Pixlet `v0.34.0` or newer installed:

```sh
pixlet render dynamic_dashboard.star
pixlet serve dynamic_dashboard.star
```

The repository also contains a small geometry test that does not require
Pixlet:

```sh
python3 tests/test_layout.py
```

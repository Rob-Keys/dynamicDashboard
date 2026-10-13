"""Applet: Dynamic Dashboard
Summary: A clock-first dashboard that tiles active signals.
Description: Shows the current time and makes room for music, precipitation,
and live games as those signals become active.
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

CANVAS_WIDTH = 64
CANVAS_HEIGHT = 32
MAX_TILES = 4

def _rect(x, y, width, height):
    return {
        "x": x,
        "y": y,
        "width": width,
        "height": height,
    }

def layout_for_count(count):
    """Return the stable one-through-four tile geometry."""
    if count <= 1:
        return [_rect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT)]
    if count == 2:
        return [
            _rect(0, 0, 32, CANVAS_HEIGHT),
            _rect(32, 0, 32, CANVAS_HEIGHT),
        ]
    if count == 3:
        return [
            _rect(0, 0, 32, 16),
            _rect(32, 0, 32, 16),
            _rect(0, 16, CANVAS_WIDTH, 16),
        ]
    return [
        _rect(0, 0, 32, 16),
        _rect(32, 0, 32, 16),
        _rect(0, 16, 32, 16),
        _rect(32, 16, 32, 16),
    ]

WIDTH = CANVAS_WIDTH
HEIGHT = CANVAS_HEIGHT

BACKGROUND = "#070a12"
TEXT = "#f4f7ff"
MUTED = "#8e9bb5"
GREEN = "#1ed760"
BLUE = "#6db5ff"
YELLOW = "#ffd166"
RED = "#ff6b6b"
HEX_DIGITS = "0123456789ABCDEF"

DEFAULT_LOCATION = """
{
  "lat": "40.6781784",
  "lng": "-73.9441579",
  "description": "Brooklyn, NY, USA",
  "timezone": "America/New_York"
}
"""

NWS_POINTS_URL = "https://api.weather.gov/points/%s,%s"
ESPN_SCOREBOARD_URL = "https://site.api.espn.com/apis/site/v2/sports/%s/scoreboard"
SPORT_PATHS = {
    "nfl": "football/nfl",
    "nba": "basketball/nba",
    "mlb": "baseball/mlb",
    "nhl": "hockey/nhl",
    "mls": "soccer/usa.1",
}

PRECIPITATION_WORDS = [
    "rain",
    "snow",
    "sleet",
    "freezing",
    "drizzle",
    "thunderstorm",
    "hail",
]

def main(config):
    timezone = config.get("$tz", "America/New_York")
    now = time.now().in_location(timezone)

    if config.bool("demo_mode", False):
        return render_layout_preview(config.str("clock_style", "custom"))

    # The clock is the one invariant item. Everything else is opt-in and
    # fail-soft so a provider outage never removes the clock.
    tiles = [{
        "kind": "clock",
        "time": now.format("15:04"),
        "hour": now.hour,
        "minute": now.minute,
        "second": now.second,
        "style": config.str("clock_style", "custom"),
    }]

    spotify = spotify_now_playing(config.str("spotify_access_token", ""))
    if spotify:
        tiles.append(spotify)

    location = json.decode(config.get("location", DEFAULT_LOCATION))
    weather = upcoming_precipitation(location)
    if weather:
        tiles.append(weather)

    live_game = find_live_game(
        config.str("followed_teams", ""),
        config.str("leagues", "nfl,nba,mlb,nhl,mls"),
    )
    if live_game:
        tiles.append(live_game)

    # MAX_TILES is also a guard for future providers. The current dashboard
    # has exactly four possible items: clock, Spotify, weather, and sports.
    tiles = tiles[:MAX_TILES]
    rectangles = layout_for_count(len(tiles))

    children = []
    for index in range(len(tiles)):
        rect = rectangles[index]
        tile = render_tile(tiles[index], rect)
        children.append(render.Padding(
            child = tile,
            # render.Padding uses (left, top, right, bottom).
            pad = (
                rect["x"],
                rect["y"],
                WIDTH - rect["x"] - rect["width"],
                HEIGHT - rect["y"] - rect["height"],
            ),
        ))

    return render.Root(
        # Re-render often enough for the clock and live signals, while HTTP
        # provider calls remain independently cached below.
        delay = 30000,
        max_age = 60,
        child = render.Box(
            width = WIDTH,
            height = HEIGHT,
            color = BACKGROUND,
            child = render.Stack(children = children),
        ),
    )

def render_layout_preview(clock_style = "custom"):
    """Render every supported layout for the README preview GIF."""
    styles = ["custom", "hexcolor", "binary"] if clock_style == "all" else [clock_style]
    frames = []
    for style in styles:
        for count in range(1, MAX_TILES + 1):
            frames.append(layout_preview_frame(count, style))
    return render.Root(
        delay = 1000 if clock_style == "all" else 1800,
        show_full_animation = True,
        child = render.Animation(children = frames),
    )

def layout_preview_frame(count, clock_style = "custom"):
    items = [
        {"kind": "clock", "time": "12:34", "hour": 12, "minute": 34, "second": 0, "style": clock_style},
        {"kind": "spotify", "title": "Midnight City", "artist": "M83", "progress": 0.62},
        {"kind": "weather", "label": "RAIN", "probability": 24, "when": "+2H"},
        {"kind": "sports", "league": "NHL", "away": "NYR", "away_score": "3", "home": "BOS", "home_score": "2"},
    ][:count]
    rectangles = layout_for_count(count)
    children = []
    for index in range(count):
        rect = rectangles[index]
        tile = render_tile(items[index], rect)
        children.append(render.Padding(
            child = tile,
            pad = (
                rect["x"],
                rect["y"],
                WIDTH - rect["x"] - rect["width"],
                HEIGHT - rect["y"] - rect["height"],
            ),
        ))
    return render.Box(
        width = WIDTH,
        height = HEIGHT,
        color = BACKGROUND,
        child = render.Stack(children = children),
    )

def render_tile(tile, rect):
    width = rect["width"]
    height = rect["height"]
    kind = tile["kind"]

    if kind == "clock":
        content = render_clock(tile, width, height)
    elif kind == "spotify":
        content = render_spotify(tile, width, height)
    elif kind == "weather":
        content = render_weather(tile, width, height)
    else:
        content = render_sports(tile, width, height)

    return render.Box(
        width = width,
        height = height,
        color = tile_color(kind),
        child = content,
    )

def tile_color(kind):
    if kind == "spotify":
        return "#07140c"
    if kind == "weather":
        return "#07121e"
    if kind == "sports":
        return "#180b0b"
    return BACKGROUND

def centered(children):
    return render.Column(
        expanded = True,
        main_align = "center",
        cross_align = "center",
        children = children,
    )

def render_clock(tile, width, height):
    """Render the selected compact clock adaptation in the allocated tile.

    Community applets are full-canvas entrypoints rather than embeddable
    plugins, so these small renderers reuse their visual approaches while
    honoring the dashboard tile's dimensions.
    """
    style = tile.get("style", "custom")
    if style == "hexcolor":
        color, foreground = clock_color(tile["hour"], tile["minute"], tile.get("second", 0))
        return render.Box(
            width = width,
            height = height,
            color = color,
            child = centered([
                render.Text(content = tile["time"], font = "6x13", color = foreground),
            ]),
        )
    if style == "binary":
        return render_binary_clock(tile["hour"], tile["minute"], width, height)
    # Adapted from the community Custom Clock. Use its compact font in quarter
    # tiles and scale up where the allocated tile permits it.
    font = "10x20" if width >= 64 else ("6x13" if height >= 32 else "5x8")
    return centered([
        render.Text(content = tile["time"], font = font, color = TEXT),
    ])

def clock_color(hour, minute, second):
    """Return the current time-derived color used by Hex Color Clock."""
    red = int((hour + minute / 60.0 + second / 3600.0) / 24.0 * 255)
    green = int((minute + second / 60.0) / 60.0 * 255)
    blue = int(second / 60.0 * 255)
    color = "#%s%s%s" % (hex_byte(red), hex_byte(green), hex_byte(blue))
    luminance = red * 0.28 + green * 0.48 + blue * 0.24
    return (color, "#000000" if luminance > 80 else "#FFFFFF")

def hex_byte(value):
    value = max(0, min(255, value))
    return HEX_DIGITS[value // 16] + HEX_DIGITS[value % 16]

def render_binary_clock(hour, minute, width, height):
    """Compact HH:MM binary-digit adaptation of the community Binary Clock."""
    digits = [hour // 10, hour % 10, minute // 10, minute % 10]
    cell_width = 5
    cell_height = 3 if height <= 16 else 4
    columns = []
    for index in range(len(digits)):
        cells = []
        for bit in range(4):
            on = (digits[index] >> (3 - bit)) & 1
            cells.append(render.Box(
                width = cell_width,
                height = cell_height,
                color = BLUE if on else "#263044",
            ))
        columns.append(render.Column(
            main_align = "center",
            cross_align = "center",
            children = cells,
        ))
        if index == 1:
            columns.append(render.Text(content = ":", font = "tom-thumb", color = MUTED))
    return centered([
        render.Row(
            main_align = "center",
            cross_align = "center",
            children = columns,
        ),
    ])

def render_spotify(tile, width, height):
    progress = tile.get("progress", -1)
    progress_bar = render_progress_bar(progress, width)
    if height <= 16:
        return render.Column(
            expanded = True,
            main_align = "space_evenly",
            cross_align = "center",
            children = [
                render.Text(content = clip(tile["title"], 10), font = "tom-thumb", color = TEXT),
                progress_bar,
            ],
        )
    return render.Column(
        expanded = True,
        main_align = "space_evenly",
        cross_align = "center",
        children = [
            render.Text(content = "SPOTIFY", font = "tom-thumb", color = GREEN),
            render.Text(content = clip(tile["title"], 12), font = "tom-thumb", color = TEXT),
            render.Text(content = clip(tile["artist"], 12), font = "tom-thumb", color = MUTED),
            progress_bar,
        ],
    )

def render_progress_bar(progress, width):
    """Small, single-item progress-bar adaptation for active Spotify playback."""
    inner_width = max(2, width - 8)
    if progress <= 0:
        return render.Box(width = inner_width, height = 2, color = "#263044")
    filled = max(1, min(inner_width, int(inner_width * min(progress, 1.0))))
    return render.Box(
        width = inner_width,
        height = 2,
        color = "#263044",
        child = render.Box(width = filled, height = 2, color = GREEN),
    )

def render_weather(tile, width, height):
    return centered([
        render.Text(content = tile["label"], font = "tom-thumb", color = BLUE),
        render.Text(content = str(tile["probability"]) + "%", font = "5x8", color = TEXT),
        render.Text(content = tile["when"], font = "tom-thumb", color = MUTED),
    ])

def render_sports(tile, width, height):
    return centered([
        render.Text(content = "LIVE " + tile["league"], font = "tom-thumb", color = RED),
        render.Text(content = clip(tile["away"], 9) + " " + tile["away_score"], font = "tom-thumb", color = TEXT),
        render.Text(content = clip(tile["home"], 9) + " " + tile["home_score"], font = "tom-thumb", color = YELLOW),
    ])

def clip(value, maximum):
    value = value or ""
    if len(value) <= maximum:
        return value
    if maximum <= 3:
        return value[:maximum]
    return value[:maximum - 3] + "..."

def spotify_now_playing(access_token):
    """Read Spotify's current playback when a valid bearer token is supplied.

    TODO(spotify-oauth): Replace the developer token field with a registered
    Tidbyt OAuth2 flow and refresh-token storage. The current implementation
    is intentionally explicit and functional for local/testing use only.
    """
    if not access_token:
        return None

    response = http.get(
        url = "https://api.spotify.com/v1/me/player",
        headers = {"Authorization": "Bearer " + access_token},
        ttl_seconds = 30,
    )
    if response.status_code != 200:
        return None

    data = response.json()
    if not data.get("is_playing", False) or not data.get("item"):
        return None

    item = data["item"]
    artists = item.get("artists", [])
    artist = artists[0].get("name", "") if artists else ""
    duration = int(item.get("duration_ms", 0))
    progress_ms = int(data.get("progress_ms", 0))
    return {
        "kind": "spotify",
        "title": item.get("name", "Now playing"),
        "artist": artist,
        "progress": float(progress_ms) / duration if duration > 0 else -1,
    }

def upcoming_precipitation(location):
    """Return the first NWS precipitation period in the next six hours."""
    # TODO(weather-global): Add a provider strategy for locations outside the
    # United States; NWS is deliberately the first, smallest implementation.
    lat = location.get("lat")
    lng = location.get("lng")
    if not lat or not lng:
        return None

    headers = {
        "User-Agent": "dynamic-dashboard-tidbyt",
        "Accept": "application/geo+json",
    }
    points = http.get(
        url = NWS_POINTS_URL % (lat, lng),
        headers = headers,
        ttl_seconds = 21600,
    )
    if points.status_code != 200:
        return None

    points_data = points.json()
    hourly_url = points_data.get("properties", {}).get("forecastHourly")
    if not hourly_url:
        return None

    forecast = http.get(url = hourly_url, headers = headers, ttl_seconds = 900)
    if forecast.status_code != 200:
        return None

    periods = forecast.json().get("properties", {}).get("periods", [])[:6]
    for index, period in enumerate(periods):
        if has_precipitation(period):
            probability = period.get("probabilityOfPrecipitation", {}).get("value")
            probability = probability if probability != None else 0
            label = precipitation_label(period.get("shortForecast", ""))
            return {
                "kind": "weather",
                "label": label,
                "probability": int(probability),
                "when": "NOW" if index == 0 else "+%dH" % index,
            }
    return None

def has_precipitation(period):
    probability = period.get("probabilityOfPrecipitation", {}).get("value")
    if probability != None and int(probability) > 0:
        return True
    description = period.get("shortForecast", "").lower()
    for word in PRECIPITATION_WORDS:
        if description.find(word) >= 0:
            return True
    return False

def precipitation_label(description):
    description = description.lower()
    if description.find("snow") >= 0 or description.find("sleet") >= 0 or description.find("freezing") >= 0:
        return "SNOW"
    if description.find("storm") >= 0 or description.find("hail") >= 0:
        return "STORM"
    return "RAIN"

def find_live_game(followed_teams, leagues):
    """Find the first ESPN event currently marked in-progress for a team."""
    # TODO(sports-selection): Add persisted team IDs, logos, and paging for
    # multiple simultaneous games after the first live-game slice is stable.
    teams = [team.strip().lower() for team in followed_teams.split(",") if team.strip()]
    if not teams:
        return None

    requested_leagues = [league.strip().lower() for league in leagues.split(",") if league.strip()]
    for league in requested_leagues:
        path = SPORT_PATHS.get(league)
        if not path:
            continue
        response = http.get(
            url = ESPN_SCOREBOARD_URL % path,
            ttl_seconds = 30,
        )
        if response.status_code != 200:
            continue

        events = response.json().get("events", [])
        for event in events:
            status = event.get("status", {}).get("type", {})
            if status.get("state") != "in":
                continue
            competitions = event.get("competitions", [])
            if not competitions:
                continue
            competitors = competitions[0].get("competitors", [])
            if not game_includes_team(competitors, teams):
                continue
            return game_tile(league, competitors)
    return None

def game_includes_team(competitors, followed_teams):
    for competitor in competitors:
        team = competitor.get("team", {})
        abbreviation = team.get("abbreviation", "").lower()
        display_name = team.get("displayName", "").lower()
        short_name = team.get("shortDisplayName", "").lower()
        for followed in followed_teams:
            if followed == abbreviation or display_name.find(followed) >= 0 or short_name.find(followed) >= 0:
                return True
    return False

def game_tile(league, competitors):
    away = competitors[0]
    home = competitors[1] if len(competitors) > 1 else competitors[0]
    if away.get("homeAway") == "home" and len(competitors) > 1:
        away = competitors[1]
        home = competitors[0]
    return {
        "kind": "sports",
        "league": league.upper(),
        "away": away.get("team", {}).get("abbreviation", "AWAY"),
        "home": home.get("team", {}).get("abbreviation", "HOME"),
        "away_score": str(away.get("score", "0")),
        "home_score": str(home.get("score", "0")),
    }

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Location(
                id = "location",
                name = "Dashboard location",
                desc = "Location used for the precipitation tile.",
                icon = "locationDot",
            ),
            schema.Toggle(
                id = "demo_mode",
                name = "Layout preview mode",
                desc = "Cycle through the one-, two-, three-, and four-tile layouts.",
                icon = "play",
                default = False,
            ),
            schema.Dropdown(
                id = "clock_style",
                name = "Clock style",
                desc = "Choose a compact clock renderer adapted from community app designs.",
                icon = "clock",
                default = "custom",
                options = [
                    schema.Option(display = "Custom Clock · clean digital", value = "custom"),
                    schema.Option(display = "Hex Color Clock · color-changing", value = "hexcolor"),
                    schema.Option(display = "Binary Clock · pixel digits", value = "binary"),
                ],
            ),
            schema.Text(
                id = "spotify_access_token",
                name = "Spotify access token",
                desc = "Optional temporary token with user-read-playback-state scope. OAuth is stubbed; see README.",
                icon = "music",
                default = "",
            ),
            schema.Text(
                id = "followed_teams",
                name = "Followed teams",
                desc = "Comma-separated team abbreviations or names, for example NYR, NYG.",
                icon = "trophy",
                default = "",
            ),
            schema.Text(
                id = "leagues",
                name = "Sports to check",
                desc = "Comma-separated ESPN leagues: nfl, nba, mlb, nhl, or mls.",
                icon = "list",
                default = "nfl,nba,mlb,nhl,mls",
            ),
        ],
    )

# ShibKart track save format

Tracks are plain **JSON** text files, extension `.track.json`. Because they're just
text, sharing a track is literally copying the file. Nothing binary, nothing hidden.

- **Player-made tracks** are saved to `user://tracks/<slug>.track.json`
  (on Windows: `%APPDATA%\Godot\app_userdata\ShibKart\tracks\`).
- **Bundled tracks** ship in `res://assets/tracks/*.track.json`.

The editor's **Save** writes to `user://tracks/`; **Load** lists both bundled and
user tracks. **Test Drive** autosaves, then races the track immediately.

## Schema (version 1)

```jsonc
{
  "format": "shibkart_track",   // required magic string — loader rejects anything else
  "version": 1,                  // format version
  "name": "Boshi Speedway",      // display name; also the saved filename slug
  "width": 240.0,                // road width in pixels (road is the centerline thickened)
  "laps": 3,                     // laps required to finish
  "start_index": 0,              // index into waypoints[] carrying the start/finish line
  "waypoints": [                 // CLOSED-LOOP centerline; last point connects to first
    [1100.0, 360.0],
    [1084.33, 422.12]
    // ... at least 3 points; each is [x, y] in world pixels
  ],
  "props": [                     // optional track features
    { "type": "boost", "pos": [1000.0, 190.0], "rot": 0.0 },
    { "type": "coin",  "pos": [640.0, 120.0],  "rot": 0.0 }
  ]
}
```

### Fields

| field         | type            | notes |
|---------------|-----------------|-------|
| `format`      | string          | must equal `"shibkart_track"` |
| `version`     | int             | currently `1` |
| `name`        | string          | shown in menus; slugged for the filename |
| `width`       | float           | road width (px); editor range 80–500 |
| `laps`        | int             | 1–9 |
| `start_index` | int             | which waypoint holds the start/finish line |
| `waypoints`   | array of `[x,y]`| closed-loop centerline, ≥ 3 points |
| `props`       | array of object | each `{ "type", "pos":[x,y], "rot" }` |

### Prop types

| type       | effect in-race |
|------------|----------------|
| `boost`    | speed boost pad |
| `coin`     | collectible, small speed nudge |
| `obstacle` | slows you on contact |
| `oil`      | slows you on contact (slick) |

## How the model uses it

- The road surface is the centerline **thickened by `width`** — each waypoint is a
  gate the racer passes in order. Passing the `start_index` waypoint after a full
  loop counts a lap.
- Checkpoints are derived from the waypoints automatically, so any valid loop is
  instantly drivable — no separate checkpoint authoring.
- Geometry helpers live in `scripts/track.gd` (`Track` class): `to_dict()`,
  `from_dict()`, `load_from()`, `save_to_user()`, `road_polygon()`,
  `distance_to_centerline()`, `is_on_road()`, `make_default()`.

## Forward-compatibility

Unknown fields are ignored on load, and missing optional fields fall back to
defaults, so adding new prop types or metadata in a later version won't break old
tracks. Bump `version` when the meaning of an existing field changes.

"""Deterministic 64x32 tile layouts for Dynamic Dashboard.

The app intentionally supports no more than four tiles. Tile order is the
order in which active dashboard items are collected, with the clock first.
"""

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
    """Return rectangles for 1..4 active tiles.

    Three tiles use two quarter tiles on the top row and one half-width tile
    on the bottom row. This makes the layout stable as providers appear and
    disappear, while preserving the requested quarter/quarter/half split.
    """
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

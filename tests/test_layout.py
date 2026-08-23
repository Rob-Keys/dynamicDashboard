"""Specification tests for the Dynamic Dashboard tile geometry.

Pixlet is not available in every development environment, so these tests
validate the public 64x32 layout contract independently of the renderer.
"""


CANVAS = (64, 32)


def layout_for_count(count):
    if count <= 1:
        return [(0, 0, 64, 32)]
    if count == 2:
        return [(0, 0, 32, 32), (32, 0, 32, 32)]
    if count == 3:
        return [(0, 0, 32, 16), (32, 0, 32, 16), (0, 16, 64, 16)]
    return [(0, 0, 32, 16), (32, 0, 32, 16), (0, 16, 32, 16), (32, 16, 32, 16)]


def assert_valid_layout(rectangles):
    assert rectangles
    assert all(width > 0 and height > 0 for _, _, width, height in rectangles)
    assert all(x >= 0 and y >= 0 for x, y, _, _ in rectangles)
    assert all(x + width <= CANVAS[0] and y + height <= CANVAS[1] for x, y, width, height in rectangles)
    assert sum(width * height for _, _, width, height in rectangles) == CANVAS[0] * CANVAS[1]

    for index, (x, y, width, height) in enumerate(rectangles):
        for other_x, other_y, other_width, other_height in rectangles[index + 1:]:
            overlaps_horizontally = x < other_x + other_width and other_x < x + width
            overlaps_vertically = y < other_y + other_height and other_y < y + height
            assert not (overlaps_horizontally and overlaps_vertically)


def test_layout_contract():
    assert layout_for_count(1) == [(0, 0, 64, 32)]
    assert layout_for_count(2) == [(0, 0, 32, 32), (32, 0, 32, 32)]
    assert layout_for_count(3) == [(0, 0, 32, 16), (32, 0, 32, 16), (0, 16, 64, 16)]
    assert layout_for_count(4) == [
        (0, 0, 32, 16),
        (32, 0, 32, 16),
        (0, 16, 32, 16),
        (32, 16, 32, 16),
    ]


def test_all_layouts_fit_canvas():
    for count in range(1, 5):
        assert_valid_layout(layout_for_count(count))


if __name__ == "__main__":
    test_layout_contract()
    test_all_layouts_fit_canvas()
    print("Dynamic Dashboard layout tests passed")

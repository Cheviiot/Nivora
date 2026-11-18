"""Render the p11 desktop icon from the logo in the upstream Happ package."""

import struct
import sys
import zlib
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SIZE = 512
MARGIN = 38
RADIUS = 116
BACKGROUND = 43
LOGO_HEIGHT = 292


def unfilter(row, previous, channels, kind):
    """Undo the PNG scanline filter in place, including the Paeth predictor."""
    if kind == 0:
        return
    if kind > 4:
        raise ValueError(f"unsupported PNG filter {kind}")
    for i, value in enumerate(row):
        left = row[i - channels] if i >= channels else 0
        up = previous[i]
        if kind == 1:
            predictor = left
        elif kind == 2:
            predictor = up
        elif kind == 3:
            predictor = (left + up) // 2
        else:
            upper_left = previous[i - channels] if i >= channels else 0
            estimate = left + up - upper_left
            predictor = min((left, up, upper_left), key=lambda v: abs(estimate - v))
        row[i] = (value + predictor) & 255


def read_logo(path):
    png = path.read_bytes()
    if not png.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG")
    compressed = bytearray()
    offset = len(PNG_SIGNATURE)
    while offset < len(png):
        length, kind = struct.unpack_from(">I4s", png, offset)
        chunk = png[offset + 8:offset + 8 + length]
        offset += length + 12
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or color not in (2, 6) or any((compression, filtering, interlace)):
                raise ValueError("expected a non-interlaced RGB or RGBA PNG")
        elif kind == b"IDAT":
            compressed.extend(chunk)
        elif kind == b"IEND":
            break

    channels = 4 if color == 6 else 3
    stride = width * channels
    raw = zlib.decompress(compressed)
    if len(raw) != (stride + 1) * height:
        raise ValueError("incorrect PNG scanline length")
    previous = bytearray(stride)
    mask = []
    left, top, right, bottom = width, height, -1, -1
    for y in range(height):
        start = y * (stride + 1)
        row = bytearray(raw[start + 1:start + 1 + stride])
        unfilter(row, previous, channels, raw[start])
        previous = row
        alpha_row = []
        for x in range(width):
            pos = x * channels
            red, green, blue = row[pos:pos + 3]
            opacity = row[pos + 3] / 255 if channels == 4 else 1.0
            luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            alpha = min(1.0, max(0.0, (luminance - BACKGROUND) / (255 - BACKGROUND))) * opacity
            alpha_row.append(alpha)
            if alpha > 0.04:
                left, right = min(left, x), max(right, x)
                top, bottom = min(top, y), max(bottom, y)
        mask.append(alpha_row)
    if right < left:
        raise ValueError("no visible Happ logo")
    return [row[left:right + 1] for row in mask[top:bottom + 1]]


def background_alpha(x, y):
    # Reflect into the top-left quadrant. Only pixels crossing the circular
    # edge need the sixteen subpixel samples used for antialiasing.
    x, y = min(x, SIZE - 1 - x), min(y, SIZE - 1 - y)
    if x < MARGIN or y < MARGIN:
        return 0
    center = MARGIN + RADIUS
    if x >= center or y >= center:
        return 255
    dx, dy = center - x, center - y
    if dx ** 2 + dy ** 2 <= RADIUS ** 2:
        return 255
    if (dx - 1) ** 2 + (dy - 1) ** 2 >= RADIUS ** 2:
        return 0
    samples = (0.125, 0.375, 0.625, 0.875)
    hits = sum((dx - sx) ** 2 + (dy - sy) ** 2 <= RADIUS ** 2 for sx in samples for sy in samples)
    return round(255 * hits / 16)


def sample_alpha(mask, x, y):
    height, width = len(mask), len(mask[0])
    if not (0 <= x <= width - 1 and 0 <= y <= height - 1):
        return 0.0
    x0, y0 = int(x), int(y)
    x1, y1 = min(x0 + 1, width - 1), min(y0 + 1, height - 1)
    dx, dy = x - x0, y - y0
    top = mask[y0][x0] * (1 - dx) + mask[y0][x1] * dx
    bottom = mask[y1][x0] * (1 - dx) + mask[y1][x1] * dx
    return top * (1 - dy) + bottom * dy


def render(mask):
    height, width = len(mask), len(mask[0])
    logo_width = round(width * LOGO_HEIGHT / height)
    left = (SIZE - logo_width) // 2
    top = (SIZE - LOGO_HEIGHT) // 2 + 6
    scanlines = bytearray()
    for y in range(SIZE):
        scanlines.append(0)  # PNG filter: none
        for x in range(SIZE):
            opacity = background_alpha(x, y)
            gray = BACKGROUND if opacity else 0
            if left <= x < left + logo_width and top <= y < top + LOGO_HEIGHT:
                source_x = (x - left + 0.5) * width / logo_width - 0.5
                source_y = (y - top + 0.5) * height / LOGO_HEIGHT - 0.5
                alpha = sample_alpha(mask, source_x, source_y)
                if alpha > 0:
                    base = opacity / 255
                    combined = alpha + base * (1 - alpha)
                    gray = round((255 * alpha + gray * base * (1 - alpha)) / combined)
                    opacity = round(255 * combined)
            scanlines.extend((gray, gray, gray, opacity))
    return scanlines


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def write_icon(source, destination):
    scanlines = render(read_logo(source))
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(
        PNG_SIGNATURE + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    write_icon(Path(sys.argv[1]), Path(sys.argv[2]))

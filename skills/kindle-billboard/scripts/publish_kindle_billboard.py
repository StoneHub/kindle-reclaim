#!/usr/bin/env python3
"""
Publish content for the Kindle billboard poller.

Writes a canonical current.png plus metadata into a publish directory that can
be exposed over HTTP by any static file server.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import socket
import subprocess
import sys
import textwrap
from datetime import date, datetime, time, timedelta, timezone
from io import BytesIO
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import urlopen

from zoneinfo import ZoneInfo

try:
    from PIL import Image, ImageDraw, ImageFont, ImageOps
except ModuleNotFoundError:  # pragma: no cover - environment dependent
    Image = ImageDraw = ImageFont = ImageOps = None

WIDTH = 600
HEIGHT = 800
DEFAULT_PORT = 8765
ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUBLISH_DIR = ROOT / "artifacts" / "publish"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def require_pillow() -> None:
    if Image is None or ImageDraw is None or ImageFont is None or ImageOps is None:
        raise RuntimeError("Pillow is required for image publishing commands. Install it with 'pip install pillow'.")


def detect_lan_ip() -> str | None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        return None if ip.startswith("127.") else ip
    except OSError:
        return None
    finally:
        sock.close()


def ensure_publish_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    (path / "history").mkdir(parents=True, exist_ok=True)
    (path / "slides").mkdir(parents=True, exist_ok=True)


def write_text_file(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8", newline="\n")


def fit_image(img: Image.Image) -> Image.Image:
    require_pillow()
    gray = img.convert("L")
    fitted = ImageOps.contain(gray, (WIDTH, HEIGHT))
    canvas = Image.new("L", (WIDTH, HEIGHT), 255)
    x = (WIDTH - fitted.width) // 2
    y = (HEIGHT - fitted.height) // 2
    canvas.paste(fitted, (x, y))
    return canvas


def save_current(img: Image.Image, publish_dir: Path, metadata: dict[str, Any]) -> Path:
    ensure_publish_dir(publish_dir)
    current_path = publish_dir / "current.png"
    history_path = publish_dir / "history" / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}.png"
    meta_path = publish_dir / "current.json"

    img.save(current_path, format="PNG", optimize=True)
    shutil.copy2(current_path, history_path)
    meta_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return current_path


def write_playlist_manifest(
    publish_dir: Path,
    entries: list[dict[str, Any]],
    *,
    metadata: dict[str, Any],
) -> None:
    ensure_publish_dir(publish_dir)
    playlist_txt = publish_dir / "playlist.txt"
    playlist_json = publish_dir / "playlist.json"
    lines = [str(entry["path"]) for entry in entries]
    write_text_file(playlist_txt, "\n".join(lines) + ("\n" if lines else ""))
    playlist_json.write_text(
        json.dumps(
            {
                "published_at": utc_now(),
                "entries": entries,
                "metadata": metadata,
            },
            indent=2,
        ),
        encoding="utf-8",
    )


def write_single_item_playlist(publish_dir: Path, metadata: dict[str, Any]) -> None:
    write_playlist_manifest(
        publish_dir,
        [{"path": "current.png", "kind": metadata.get("kind", "image")}],
        metadata=metadata,
    )


def normalize_hour_minute(value: datetime) -> tuple[int, int]:
    return value.hour, value.minute


def normalize_degrees(value: float) -> float:
    while value < 0:
        value += 360
    while value >= 360:
        value -= 360
    return value


def normalize_hours(value: float) -> float:
    while value < 0:
        value += 24
    while value >= 24:
        value -= 24
    return value


def calculate_sun_event_utc(day: date, latitude: float, longitude: float, *, sunrise: bool) -> datetime | None:
    day_of_year = day.timetuple().tm_yday
    lng_hour = longitude / 15.0
    approx_time = day_of_year + ((6 - lng_hour) / 24.0 if sunrise else (18 - lng_hour) / 24.0)

    mean_anomaly = (0.9856 * approx_time) - 3.289
    true_longitude = mean_anomaly + (1.916 * math.sin(math.radians(mean_anomaly)))
    true_longitude += 0.020 * math.sin(math.radians(2 * mean_anomaly)) + 282.634
    true_longitude = normalize_degrees(true_longitude)

    right_ascension = math.degrees(math.atan(0.91764 * math.tan(math.radians(true_longitude))))
    right_ascension = normalize_degrees(right_ascension)
    true_longitude_quadrant = math.floor(true_longitude / 90) * 90
    right_ascension_quadrant = math.floor(right_ascension / 90) * 90
    right_ascension = (right_ascension + (true_longitude_quadrant - right_ascension_quadrant)) / 15.0

    sin_declination = 0.39782 * math.sin(math.radians(true_longitude))
    cos_declination = math.cos(math.asin(sin_declination))
    cos_hour_angle = (
        math.cos(math.radians(90.833))
        - (sin_declination * math.sin(math.radians(latitude)))
    ) / (cos_declination * math.cos(math.radians(latitude)))

    if cos_hour_angle > 1 or cos_hour_angle < -1:
        return None

    hour_angle = 360 - math.degrees(math.acos(cos_hour_angle)) if sunrise else math.degrees(math.acos(cos_hour_angle))
    hour_angle /= 15.0

    local_mean_time = hour_angle + right_ascension - (0.06571 * approx_time) - 6.622
    universal_time = normalize_hours(local_mean_time - lng_hour)
    return datetime.combine(day, time(0, 0), tzinfo=timezone.utc) + timedelta(hours=universal_time)


def write_daylight_env(
    publish_dir: Path,
    *,
    fixed_start_hour: int = 7,
    fixed_end_hour: int = 21,
) -> Path:
    ensure_publish_dir(publish_dir)
    output = publish_dir / "daylight.env"

    latitude_text = os.environ.get("KINDLE_BILLBOARD_LATITUDE", "").strip()
    longitude_text = os.environ.get("KINDLE_BILLBOARD_LONGITUDE", "").strip()
    timezone_name = os.environ.get("KINDLE_BILLBOARD_TIMEZONE", "").strip()

    start_hour = fixed_start_hour
    start_minute = 0
    end_hour = fixed_end_hour
    end_minute = 0
    source = "fixed"

    if latitude_text and longitude_text:
        try:
            latitude = float(latitude_text)
            longitude = float(longitude_text)
            zone = ZoneInfo(timezone_name) if timezone_name else datetime.now().astimezone().tzinfo
            if zone is not None:
                today = datetime.now(zone).date()
                sunrise_utc = calculate_sun_event_utc(today, latitude, longitude, sunrise=True)
                sunset_utc = calculate_sun_event_utc(today, latitude, longitude, sunrise=False)
                if sunrise_utc and sunset_utc:
                    sunrise_local = sunrise_utc.astimezone(zone)
                    sunset_local = sunset_utc.astimezone(zone)
                    start_hour, start_minute = normalize_hour_minute(sunrise_local)
                    end_hour, end_minute = normalize_hour_minute(sunset_local)
                    source = "sunrise_sunset"
        except Exception:
            source = "fixed"

    content = "\n".join(
        [
            f"DATE={datetime.now().date().isoformat()}",
            f"DAY_START_HOUR={start_hour}",
            f"DAY_START_MINUTE={start_minute}",
            f"DAY_END_HOUR={end_hour}",
            f"DAY_END_MINUTE={end_minute}",
            f"DAY_WINDOW_SOURCE={source}",
            "",
        ]
    )
    write_text_file(output, content)
    return output


def load_image_from_bytes(raw: bytes) -> Image.Image:
    require_pillow()
    return Image.open(BytesIO(raw))


def open_local_or_remote(source: str) -> tuple[Image.Image, dict[str, Any]]:
    require_pillow()
    parsed = urlparse(source)
    if parsed.scheme in {"http", "https"}:
        with urlopen(source) as response:  # nosec - caller explicitly requested the URL
            raw = response.read()
        return load_image_from_bytes(raw), {"source_type": "url", "source": source}

    path = Path(source).expanduser().resolve()
    suffix = path.suffix.lower()
    if suffix == ".pdf":
        raise RuntimeError(
            "PDF rasterization is not implemented here. Convert the PDF to PNG first, "
            "or add pdftoppm/magick support on the host."
        )
    return Image.open(path), {"source_type": "file", "source": str(path)}


def default_font(size: int) -> ImageFont.ImageFont:
    require_pillow()
    for font_name in ("DejaVuSans.ttf", "Arial.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(font_name, size=size)
        except OSError:
            continue
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def normalized_source_name(source_name: str, source_url: str) -> str:
    if source_name.strip():
        return source_name.strip()
    if not source_url.strip():
        return ""
    hostname = urlparse(source_url).netloc.lower()
    if hostname.startswith("www."):
        hostname = hostname[4:]
    return hostname


def draw_wrapped(
    draw: ImageDraw.ImageDraw,
    text: str,
    *,
    x: int,
    y: int,
    width: int,
    font: ImageFont.ImageFont,
    line_gap: int = 8,
) -> int:
    if not text.strip():
        return y

    avg_char_px = max(8, int(font.size * 0.6)) if hasattr(font, "size") else 12
    wrap_width = max(8, width // avg_char_px)
    lines = textwrap.wrap(text.strip(), width=wrap_width, break_long_words=False) or [text.strip()]
    for line in lines:
        draw.text((x, y), line, fill=0, font=font)
        bbox = draw.textbbox((x, y), line, font=font)
        y = bbox[3] + line_gap
    return y


def render_text_card(title: str, body: str, footer: str) -> Image.Image:
    require_pillow()
    img = Image.new("L", (WIDTH, HEIGHT), 255)
    draw = ImageDraw.Draw(img)
    title_font = default_font(32)
    body_font = default_font(22)
    footer_font = default_font(18)

    draw.rectangle((20, 20, WIDTH - 21, HEIGHT - 21), outline=0, width=3)
    draw.line((20, 120, WIDTH - 20, 120), fill=0, width=2)

    y = 44
    y = draw_wrapped(draw, title, x=40, y=y, width=WIDTH - 80, font=title_font, line_gap=10)
    y = max(y, 145)
    y = draw_wrapped(draw, body, x=40, y=y, width=WIDTH - 80, font=body_font, line_gap=10)

    if footer.strip():
        footer_bbox = draw.multiline_textbbox((0, 0), footer, font=footer_font)
        footer_height = footer_bbox[3] - footer_bbox[1]
        footer_y = HEIGHT - 40 - footer_height
        draw.line((20, footer_y - 18, WIDTH - 20, footer_y - 18), fill=0, width=2)
        draw_wrapped(draw, footer, x=40, y=footer_y, width=WIDTH - 80, font=footer_font, line_gap=6)

    return img


def render_news_meme_card(
    *,
    headline: str,
    joke: str,
    summary: str,
    source_name: str,
    image: Image.Image | None,
    footer: str,
) -> Image.Image:
    require_pillow()
    img = Image.new("L", (WIDTH, HEIGHT), 255)
    draw = ImageDraw.Draw(img)
    label_font = default_font(18)
    title_font = default_font(28)
    body_font = default_font(22)
    meta_font = default_font(16)

    draw.rectangle((20, 20, WIDTH - 21, HEIGHT - 21), outline=0, width=3)

    header = "Daily News Meme"
    if source_name:
        header = f"{header} | {source_name}"
    draw.text((40, 38), header, fill=0, font=label_font)
    header_bbox = draw.textbbox((40, 38), header, font=label_font)
    divider_y = header_bbox[3] + 12
    draw.line((40, divider_y, WIDTH - 40, divider_y), fill=0, width=2)

    y = divider_y + 18
    if image is not None:
        image_top = y
        image_bottom = y + 320
        draw.rectangle((40, image_top, WIDTH - 40, image_bottom), outline=0, width=2)
        fitted = ImageOps.contain(image.convert("L"), (WIDTH - 84, 304))
        paste_x = (WIDTH - fitted.width) // 2
        paste_y = image_top + ((image_bottom - image_top) - fitted.height) // 2
        img.paste(fitted, (paste_x, paste_y))
        y = image_bottom + 18

    y = draw_wrapped(draw, headline, x=40, y=y, width=WIDTH - 80, font=title_font, line_gap=8)

    if joke.strip():
        y += 6
        y = draw_wrapped(draw, joke, x=40, y=y, width=WIDTH - 80, font=body_font, line_gap=8)

    if summary.strip():
        y += 8
        y = draw_wrapped(draw, summary, x=40, y=y, width=WIDTH - 80, font=meta_font, line_gap=6)

    footer_lines = [line.strip() for line in (source_name, footer) if line.strip()]
    if footer_lines:
        footer_text = "\n".join(footer_lines)
        footer_bbox = draw.multiline_textbbox((0, 0), footer_text, font=meta_font, spacing=4)
        footer_height = footer_bbox[3] - footer_bbox[1]
        footer_y = max(y + 16, HEIGHT - 42 - footer_height)
        draw.line((40, footer_y - 14, WIDTH - 40, footer_y - 14), fill=0, width=2)
        draw.multiline_text((40, footer_y), footer_text, fill=0, font=meta_font, spacing=4)

    return img


def cmd_status(args: argparse.Namespace) -> int:
    publish_dir = Path(args.publish_dir).resolve()
    guessed_ip = args.host_ip or detect_lan_ip()
    write_daylight_env(publish_dir)
    current_path = publish_dir / "current.png"
    current_meta = publish_dir / "current.json"
    payload = {
        "publish_dir": str(publish_dir),
        "current_exists": current_path.exists(),
        "current_path": str(current_path),
        "metadata_path": str(current_meta),
        "guessed_current_url": (
            f"http://{guessed_ip}:{args.port}/current.png" if guessed_ip else None
        ),
        "guessed_playlist_url": (
            f"http://{guessed_ip}:{args.port}/playlist.txt" if guessed_ip else None
        ),
        "guessed_daylight_url": (
            f"http://{guessed_ip}:{args.port}/daylight.env" if guessed_ip else None
        ),
        "notes": [
            "Untethered updates require the Kindle poll loop to already be running.",
            "Publishing a new current.png is the normal push path.",
        ],
    }
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def cmd_publish_file(args: argparse.Namespace) -> int:
    publish_dir = Path(args.publish_dir).resolve()
    img, source_meta = open_local_or_remote(args.source)
    fitted = fit_image(img)
    metadata = {
        "kind": "image",
        "published_at": utc_now(),
        "note": args.note or "",
        **source_meta,
    }
    current = save_current(fitted, publish_dir, metadata)
    write_single_item_playlist(publish_dir, metadata)
    write_daylight_env(publish_dir)
    print(current)
    return 0


def cmd_publish_text(args: argparse.Namespace) -> int:
    publish_dir = Path(args.publish_dir).resolve()
    img = render_text_card(args.title, args.body, args.footer)
    metadata = {
        "kind": "text",
        "published_at": utc_now(),
        "source_type": "generated",
        "title": args.title,
        "footer": args.footer,
    }
    current = save_current(img, publish_dir, metadata)
    write_single_item_playlist(publish_dir, metadata)
    write_daylight_env(publish_dir)
    print(current)
    return 0


def cmd_publish_news_meme(args: argparse.Namespace) -> int:
    publish_dir = Path(args.publish_dir).resolve()
    image = None
    image_meta: dict[str, Any] = {}
    if args.image:
        image, image_meta = open_local_or_remote(args.image)

    source_name = normalized_source_name(args.source_name, args.source_url)
    img = render_news_meme_card(
        headline=args.headline,
        joke=args.joke,
        summary=args.summary,
        source_name=source_name,
        image=image,
        footer=args.footer,
    )
    metadata = {
        "kind": "news_meme",
        "published_at": utc_now(),
        "source_type": "generated",
        "headline": args.headline,
        "joke": args.joke,
        "summary": args.summary,
        "source_name": source_name,
        "source_url": args.source_url,
        "footer": args.footer,
    }
    if image_meta:
        metadata["image"] = image_meta
    current = save_current(img, publish_dir, metadata)
    write_single_item_playlist(publish_dir, metadata)
    write_daylight_env(publish_dir)
    print(current)
    return 0


def cmd_publish_playlist(args: argparse.Namespace) -> int:
    publish_dir = Path(args.publish_dir).resolve()
    ensure_publish_dir(publish_dir)
    slides_dir = publish_dir / "slides"
    for old_slide in slides_dir.glob("*.png"):
        old_slide.unlink()

    entries: list[dict[str, Any]] = []
    for index, source in enumerate(args.sources, start=1):
        img, source_meta = open_local_or_remote(source)
        fitted = fit_image(img)
        relative_path = f"slides/{index:03d}.png"
        output_path = publish_dir / relative_path
        fitted.save(output_path, format="PNG", optimize=True)
        entries.append(
            {
                "path": relative_path,
                "index": index - 1,
                **source_meta,
            }
        )

    if not entries:
        raise RuntimeError("Playlist requires at least one image source.")

    shutil.copy2(publish_dir / entries[0]["path"], publish_dir / "current.png")
    metadata = {
        "kind": "playlist",
        "published_at": utc_now(),
        "count": len(entries),
        "note": args.note or "",
    }
    (publish_dir / "current.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    write_playlist_manifest(publish_dir, entries, metadata=metadata)
    write_daylight_env(publish_dir)
    print(publish_dir / "playlist.txt")
    return 0


def cmd_refresh_daylight(args: argparse.Namespace) -> int:
    output = write_daylight_env(
        Path(args.publish_dir).resolve(),
        fixed_start_hour=args.day_start_hour,
        fixed_end_hour=args.day_end_hour,
    )
    print(output)
    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    publish_dir = Path(args.publish_dir).resolve()
    ensure_publish_dir(publish_dir)
    write_daylight_env(publish_dir)
    os.chdir(publish_dir)
    cmd = [
        sys.executable,
        "-m",
        "http.server",
        str(args.port),
        "--bind",
        args.host,
    ]
    return subprocess.call(cmd)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Host-side publisher for the Kindle billboard.")
    parser.add_argument(
        "--publish-dir",
        default=str(DEFAULT_PUBLISH_DIR),
        help=f"Directory that exposes current.png (default: {DEFAULT_PUBLISH_DIR})",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    status = subparsers.add_parser("status", help="Print current publish state as JSON.")
    status.add_argument("--host-ip", default="", help="Override the guessed LAN IP.")
    status.add_argument("--port", type=int, default=DEFAULT_PORT, help="Serving port.")
    status.set_defaults(func=cmd_status)

    publish_file = subparsers.add_parser(
        "publish-file",
        help="Publish a local image file or remote image URL as current.png.",
    )
    publish_file.add_argument("source", help="Path or http(s) URL to an image file.")
    publish_file.add_argument("--note", default="", help="Optional note stored in metadata.")
    publish_file.set_defaults(func=cmd_publish_file)

    publish_playlist = subparsers.add_parser(
        "publish-playlist",
        help="Publish multiple images as a rotating playlist and keep current.png as the first slide.",
    )
    publish_playlist.add_argument("sources", nargs="+", help="Paths or http(s) URLs to image files.")
    publish_playlist.add_argument("--note", default="", help="Optional note stored in metadata.")
    publish_playlist.set_defaults(func=cmd_publish_playlist)

    publish_text = subparsers.add_parser(
        "publish-text",
        help="Render a simple text card and publish it as current.png.",
    )
    publish_text.add_argument("--title", required=True, help="Headline at the top of the card.")
    publish_text.add_argument("--body", required=True, help="Main content.")
    publish_text.add_argument("--footer", default="", help="Optional footer line(s).")
    publish_text.set_defaults(func=cmd_publish_text)

    publish_news_meme = subparsers.add_parser(
        "publish-news-meme",
        help="Render a Kindle-optimized news meme card, with or without a supplied image.",
    )
    publish_news_meme.add_argument("--headline", required=True, help="The news headline to show.")
    publish_news_meme.add_argument(
        "--joke",
        default="",
        help="Short funny line or caption. Keep it concise for e-ink readability.",
    )
    publish_news_meme.add_argument(
        "--summary",
        default="",
        help="Optional one- or two-line context summary under the joke.",
    )
    publish_news_meme.add_argument(
        "--source-name",
        default="",
        help="Display name for the source, such as Reuters or AP News.",
    )
    publish_news_meme.add_argument(
        "--source-url",
        default="",
        help="Original article URL stored in metadata.",
    )
    publish_news_meme.add_argument(
        "--image",
        default="",
        help="Optional local path or http(s) URL for a generated meme image.",
    )
    publish_news_meme.add_argument(
        "--footer",
        default="",
        help="Optional footer, such as the agent name or schedule timestamp.",
    )
    publish_news_meme.set_defaults(func=cmd_publish_news_meme)

    serve = subparsers.add_parser("serve", help="Serve the publish directory over HTTP.")
    serve.add_argument("--host", default="0.0.0.0", help="Bind address.")
    serve.add_argument("--port", type=int, default=DEFAULT_PORT, help="Serving port.")
    serve.set_defaults(func=cmd_serve)

    refresh_daylight = subparsers.add_parser(
        "refresh-daylight",
        help="Write daylight.env for the current day using configured coordinates or fixed hours.",
    )
    refresh_daylight.add_argument("--day-start-hour", type=int, default=7, help="Fallback daytime start hour.")
    refresh_daylight.add_argument("--day-end-hour", type=int, default=21, help="Fallback daytime end hour.")
    refresh_daylight.set_defaults(func=cmd_refresh_daylight)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except Exception as exc:  # pragma: no cover - CLI wrapper
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

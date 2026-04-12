#!/usr/bin/env python3
"""
Publish content for the Kindle billboard poller.

Writes a canonical current.png plus metadata into a publish directory that can
be exposed over HTTP by any static file server.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import textwrap
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import urlopen

from PIL import Image, ImageDraw, ImageFont, ImageOps

WIDTH = 600
HEIGHT = 800
DEFAULT_PORT = 8765
ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUBLISH_DIR = ROOT / "artifacts" / "publish"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


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


def fit_image(img: Image.Image) -> Image.Image:
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


def load_image_from_bytes(raw: bytes) -> Image.Image:
    return Image.open(BytesIO(raw))


def open_local_or_remote(source: str) -> tuple[Image.Image, dict[str, Any]]:
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
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


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


def cmd_status(args: argparse.Namespace) -> int:
    publish_dir = Path(args.publish_dir).resolve()
    guessed_ip = args.host_ip or detect_lan_ip()
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
    print(current)
    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    publish_dir = Path(args.publish_dir).resolve()
    ensure_publish_dir(publish_dir)
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

    publish_text = subparsers.add_parser(
        "publish-text",
        help="Render a simple text card and publish it as current.png.",
    )
    publish_text.add_argument("--title", required=True, help="Headline at the top of the card.")
    publish_text.add_argument("--body", required=True, help="Main content.")
    publish_text.add_argument("--footer", default="", help="Optional footer line(s).")
    publish_text.set_defaults(func=cmd_publish_text)

    serve = subparsers.add_parser("serve", help="Serve the publish directory over HTTP.")
    serve.add_argument("--host", default="0.0.0.0", help="Bind address.")
    serve.add_argument("--port", type=int, default=DEFAULT_PORT, help="Serving port.")
    serve.set_defaults(func=cmd_serve)

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

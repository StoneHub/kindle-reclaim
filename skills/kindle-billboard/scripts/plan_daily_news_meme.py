#!/usr/bin/env python3
"""
Prepare a Tavily-backed daily news brief for an external meme/image agent.

This script does not generate the final joke or image. It selects a fresh story,
writes a structured plan JSON file, and emits an agent-ready prompt so another
bot can create the meme and publish it with publish_kindle_billboard.py.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUTPUT = ROOT / "artifacts" / "news-plans" / "latest.json"
TAVILY_SEARCH_URL = "https://api.tavily.com/search"
DEFAULT_INCLUDE_DOMAINS = (
    "reuters.com",
    "apnews.com",
    "bbc.com",
    "npr.org",
)
DEFAULT_EXCLUDE_DOMAINS: tuple[str, ...] = ()


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_title(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", title.lower()).strip()


def normalize_source_name(source_name: str, source_url: str) -> str:
    if source_name.strip():
        return source_name.strip()
    host = urlparse(source_url).netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    return host


def tavily_search(api_key: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = Request(
        TAVILY_SEARCH_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        retry_after = exc.headers.get("retry-after")
        detail = f"Tavily search failed with HTTP {exc.code}"
        if retry_after:
            detail = f"{detail}; retry-after={retry_after}s"
        raise RuntimeError(f"{detail}: {body}") from exc
    except URLError as exc:
        raise RuntimeError(f"Tavily search failed: {exc.reason}") from exc


def pick_story(results: list[dict[str, Any]], min_score: float) -> dict[str, Any]:
    seen_titles: set[str] = set()
    candidates: list[dict[str, Any]] = []

    for item in results:
        title = str(item.get("title") or "").strip()
        if not title:
            continue
        normalized = normalize_title(title)
        if normalized in seen_titles:
            continue
        seen_titles.add(normalized)

        score = float(item.get("score") or 0.0)
        if score >= min_score:
            candidates.append(item)

    if candidates:
        return max(candidates, key=lambda item: float(item.get("score") or 0.0))
    if results:
        return results[0]
    raise RuntimeError("Tavily returned no results.")


def build_agent_prompt(plan: dict[str, Any]) -> str:
    story = plan["story"]
    return "\n".join(
        [
            "Use this Tavily-vetted news brief to make one original Kindle billboard meme.",
            "",
            f"Headline: {story['headline']}",
            f"Source: {story['source_name']}",
            f"URL: {story['source_url']}",
            f"Summary: {story['summary']}",
            "",
            "Output requirements:",
            "- One short joke or caption, under 90 characters.",
            "- One original image suitable for 600x800 grayscale e-ink.",
            "- High contrast, one focal subject, minimal background clutter.",
            "- Avoid tiny labels, watermarks, screenshots, or color-dependent jokes.",
            "",
            "After generating the image, publish it with:",
            plan["publish_command_example"],
        ]
    )


def build_plan(args: argparse.Namespace, response: dict[str, Any], story: dict[str, Any]) -> dict[str, Any]:
    source_url = str(story.get("url") or "")
    source_name = normalize_source_name("", source_url)
    summary = str(story.get("content") or "").strip()
    headline = str(story.get("title") or "").strip()

    plan: dict[str, Any] = {
        "generated_at": utc_now(),
        "workflow": "daily_news_meme",
        "story": {
            "headline": headline,
            "summary": summary,
            "source_name": source_name,
            "source_url": source_url,
            "score": float(story.get("score") or 0.0),
        },
        "selection_policy": {
            "min_score": args.min_score,
            "picked_top_scored_result": True,
        },
        "tavily_request": {
            "query": args.query,
            "topic": "news",
            "time_range": args.time_range,
            "search_depth": args.search_depth,
            "max_results": args.max_results,
            "include_domains": list(args.include_domain),
            "exclude_domains": list(args.exclude_domain),
            "auto_parameters": False,
            "include_usage": True,
        },
        "tavily_response_meta": {
            "request_id": response.get("request_id"),
            "response_time": response.get("response_time"),
            "usage": response.get("usage", {}),
        },
        "image_prompt": (
            "Create one funny editorial-cartoon or meme-style image about this headline: "
            f"{headline}. Use a style that reads well on a 600x800 grayscale Kindle screen: "
            "high contrast, bold shapes, one main subject, sparse background, no tiny text, "
            "no watermark, no screenshot aesthetic."
        ),
        "caption_task": (
            "Write one short joke or caption for this story. Keep it under 90 characters and "
            "readable on an e-ink display."
        ),
        "publish_command_example": (
            'python skills/kindle-billboard/scripts/publish_kindle_billboard.py '
            'publish-news-meme '
            '--headline "<headline>" '
            '--joke "<short joke>" '
            '--summary "<short summary>" '
            '--source-name "<source>" '
            '--source-url "<url>" '
            '--image "/absolute/path/to/news-meme.png" '
            '--footer "OpenClaw daily cron"'
        ),
    }
    plan["agent_prompt"] = build_agent_prompt(plan)
    return plan


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare a daily Tavily-backed news plan for Kindle meme publishing."
    )
    parser.add_argument(
        "--query",
        default="top news headlines today",
        help="Tavily query used to pick the story.",
    )
    parser.add_argument(
        "--time-range",
        default="day",
        choices=("day", "week", "month", "year"),
        help="Freshness filter passed to Tavily.",
    )
    parser.add_argument(
        "--search-depth",
        default="basic",
        choices=("basic", "fast", "ultra-fast", "advanced"),
        help="Tavily search depth. basic is the recommended default here.",
    )
    parser.add_argument(
        "--max-results",
        type=int,
        default=5,
        help="Number of Tavily results to inspect before picking a story.",
    )
    parser.add_argument(
        "--min-score",
        type=float,
        default=0.7,
        help="Minimum Tavily relevance score before falling back to the top result anyway.",
    )
    parser.add_argument(
        "--include-domain",
        action="append",
        default=list(DEFAULT_INCLUDE_DOMAINS),
        help="Domain whitelist for news sources. Repeat to add more entries.",
    )
    parser.add_argument(
        "--exclude-domain",
        action="append",
        default=list(DEFAULT_EXCLUDE_DOMAINS),
        help="Domain blacklist. Repeat to add more entries.",
    )
    parser.add_argument(
        "--output",
        default=str(DEFAULT_OUTPUT),
        help=f"JSON output path (default: {DEFAULT_OUTPUT})",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    api_key = os.environ.get("TAVILY_API_KEY", "").strip()
    if not api_key:
        print("ERROR: TAVILY_API_KEY is not set.", file=sys.stderr)
        return 1

    payload = {
        "query": args.query,
        "topic": "news",
        "time_range": args.time_range,
        "search_depth": args.search_depth,
        "max_results": args.max_results,
        "include_domains": list(args.include_domain),
        "exclude_domains": list(args.exclude_domain),
        "include_usage": True,
        "auto_parameters": False,
    }

    try:
        response = tavily_search(api_key, payload)
        story = pick_story(list(response.get("results") or []), args.min_score)
    except Exception as exc:  # pragma: no cover - CLI wrapper
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    plan = build_plan(args, response, story)
    output_path = Path(args.output).expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(plan, indent=2), encoding="utf-8")
    json.dump(plan, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

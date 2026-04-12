# Daily News Meme Workflow

Use this workflow when the Kindle billboard should show one funny image or joke card about a fresh news story each day.

## Why This Shape

For this repo, the safest low-noise pipeline is:

1. Tavily Search selects one current story from trusted news domains.
2. An external agent writes one short joke and creates one original image.
3. `publish-news-meme` renders the final `600x800` Kindle card.
4. The Kindle poller fetches the updated `current.png` over Wi-Fi.

This keeps the Kindle simple, keeps the source selection fresh, and lets the agent do the creative step.

## Recommended Tavily Search Parameters

Use Tavily Search, not Tavily Research, for the daily cron selector:

- `query`: `top news headlines today`
- `topic`: `news`
- `time_range`: `day`
- `search_depth`: `basic`
- `max_results`: `5`
- `auto_parameters`: `false`
- `include_usage`: `true`
- `include_domains`: `reuters.com`, `apnews.com`, `bbc.com`, `npr.org`

Why:

- `topic=news` is the documented path for real-time current events.
- `time_range=day` keeps the story fresh.
- `search_depth=basic` keeps credit use predictable unless you have a stronger reason to pay for `advanced`.
- a short allowlist reduces junk, SEO spam, and thin aggregator pages.

Tavily docs used:

- [Search endpoint](https://docs.tavily.com/documentation/api-reference/endpoint/search)
- [Search best practices](https://docs.tavily.com/documentation/best-practices/best-practices-search)
- [Rate limits](https://docs.tavily.com/documentation/rate-limits)

## OpenClaw Cron Flow

Suggested daily job:

1. run `python skills/kindle-billboard/scripts/plan_daily_news_meme.py`
   - requires `TAVILY_API_KEY` in the job environment
2. read `artifacts/news-plans/latest.json`
3. use the `agent_prompt`, `image_prompt`, and `caption_task`
4. generate:
   - one short joke
   - one original high-contrast image
5. publish with:

```bash
python skills/kindle-billboard/scripts/publish_kindle_billboard.py \
  publish-news-meme \
  --headline "..." \
  --joke "..." \
  --summary "..." \
  --source-name "Reuters" \
  --source-url "https://..." \
  --image /absolute/path/to/news-meme.png \
  --footer "OpenClaw daily cron"
```

If the image step fails, OpenClaw can still publish a text-first fallback by omitting `--image`.

## E-Ink Constraints

Keep the creative output friendly to the screen:

- one focal subject
- high contrast
- sparse background
- no tiny labels
- no color-dependent punchlines
- keep joke text under about 90 characters
- do not rely on browser screenshots or dense article layouts

## Credit and Failure Discipline

- one daily `search` call is enough for the selector step
- log Tavily `usage` and `request_id` from the generated plan JSON
- if Tavily returns no strong result, either:
  - widen the domain allowlist a little, or
  - keep the prior billboard image instead of pushing weak junk
- if Tavily returns `429`, respect `retry-after`

## What This Repo Does Not Do

This repo does not scrape meme pages or social feeds for you.

That is deliberate:

- scraped memes are legally and operationally messy
- article screenshots usually look bad on `600x800` grayscale
- original generated art gives the agents more control and produces cleaner Kindle output

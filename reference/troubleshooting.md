# Firecrawl Troubleshooting & Configuration

## Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| 429 Too Many Requests | Rate limit exceeded | Script auto-retries with next API key; fails only after all keys exhausted |
| 401 Unauthorized | Invalid or missing API key | Check FIRECRAWL_API_KEY is set correctly |
| 402 Payment Required | Insufficient credits | Top up at https://firecrawl.dev/ |
| 400 Bad Request | Invalid parameters | Check URL format and parameter values |
| 5xx Server Error | Firecrawl service issue | Retry after brief wait |

## Environment Configuration

```bash
# Single API key
export FIRECRAWL_API_KEY="fc-your-key-here"

# Multiple API keys (comma-separated) - rotated with automatic 429 failover
export FIRECRAWL_API_KEY="fc-key1,fc-key2,fc-key3"

# Get a key at: https://firecrawl.dev/
```

## Rate Limits

| Plan | /scrape | /map | /crawl | /search |
|------|---------|------|--------|---------|
| Free | 10/min | 10/min | 1/min | 5/min |
| Hobby | 100/min | 100/min | 15/min | 50/min |
| Standard | 500/min | 500/min | 50/min | 250/min |
| Growth | 5000/min | 5000/min | 250/min | 2500/min |

## Common Issues

### URL Format

Always include the full URL with protocol:

| Bad | Good |
|-----|------|
| `example.com` | `https://example.com` |
| `docs.firecrawl.dev/api` | `https://docs.firecrawl.dev/api` |

### Scrape Format Selection

| Need | Format |
|------|--------|
| Text content for LLM | `markdown` (default) |
| Raw HTML | `html` |
| All links on page | `links` |
| Visual capture | `screenshot` |

### Map vs Crawl

| Use Map | Use Crawl |
|---------|-----------|
| Just need list of URLs | Need page content |
| Fast discovery | Deep extraction |
| Selective scraping after | Bulk content retrieval |

### Extract Prompts

Good extraction prompts are specific:

| Bad Prompt | Good Prompt |
|------------|-------------|
| "Get the data" | "Extract company name, founding year, and pricing tiers as JSON" |
| "Find info" | "Extract all product names with their prices and descriptions" |

## Script Timeouts

The script uses a 60-second timeout. For crawl operations on large sites, the script polls for completion for up to 60 seconds. For longer crawls, the job ID is returned for manual status checking.

## Credits Usage

| Operation | Credits |
|-----------|---------|
| Scrape (basic) | 1 per page |
| Scrape (stealth proxy) | 5 per page |
| Search | 2 per 10 results + scrape costs |
| Map | 1 per request |
| Crawl | 1 per page crawled |
| Extract (JSON mode) | 5 per page |

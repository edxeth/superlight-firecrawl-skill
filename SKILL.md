---
name: firecrawl
description: Scrapes and crawls web pages, converting them to clean markdown or structured JSON for LLM consumption. Use when needing to extract content from URLs, crawl entire websites, map site structure, search the web with scraping, or extract structured data from pages. Best for web scraping, site crawling, URL discovery, and converting web content to LLM-ready formats.
---

# Firecrawl Web Scraping

Converts web pages into clean, LLM-ready markdown or structured data. Handles JavaScript rendering, anti-bot measures, PDFs, and complex sites. No output truncation.

## When to Use

| Situation | Use Firecrawl | Don't use Firecrawl |
|---|---|---|
| Parse PDFs | `scrape` with parsers option | — |
| Discover all URLs on a site | `map` then `batch-scrape` | — |
| Scrape 5+ pages in parallel | `batch-scrape` | — |
| Crawl entire site recursively | `crawl` with depth | — |
| Extract structured JSON | `extract` with prompt | — |
| Anti-bot / Cloudflare sites | `scrape` with `"proxy":"stealth"` | — |
| Fetch a single HTML page | — | Use TinyFish (returns more content) |
| Semantic web search | — | Use Exa `search` |

**Firecrawl is for crawling, mapping, PDFs, and structure. TinyFish beats it for single-page HTML.**

## Protocol

### Scrape a Single URL

```bash
scripts/firecrawl.sh scrape "<url>" [format] [options-json]
```

**Formats:** `markdown` (default), `html`, `links`, `screenshot`

**Options JSON** (optional 3rd arg): `{"waitFor":3000,"proxy":"stealth","parsers":[{"type":"pdf","mode":"ocr"}]}`

**Examples:**
```bash
scripts/firecrawl.sh scrape "https://docs.firecrawl.dev/introduction"
scripts/firecrawl.sh scrape "https://spa-app.com" markdown '{"waitFor":3000}'
scripts/firecrawl.sh scrape "https://arxiv.org/pdf/2301.00001" markdown '{"parsers":[{"type":"pdf"}]}'
```

### Batch Scrape Multiple URLs

```bash
scripts/firecrawl.sh batch-scrape '<urls-json-array>' [format] [options-json]
```

Processes multiple URLs in parallel via job polling. Use after `map` to scrape discovered pages.

**Examples:**
```bash
scripts/firecrawl.sh batch-scrape '["https://a.com","https://b.com","https://c.com"]' markdown
scripts/firecrawl.sh batch-scrape '["https://docs.site.com/api","https://docs.site.com/guide"]' markdown '{"waitFor":2000}'
```

### Search Web + Scrape Results

```bash
scripts/firecrawl.sh search "<query>" [limit]
```

### Map Website URLs

```bash
scripts/firecrawl.sh map "<url>" [limit] [search]
```

Discovers all URLs on a site. Use as first step before batch-scrape.

**Examples:**
```bash
scripts/firecrawl.sh map "https://firecrawl.dev" 50
scripts/firecrawl.sh map "https://docs.firecrawl.dev" 100 "api reference"
```

### Extract Structured JSON

```bash
scripts/firecrawl.sh extract "<url>" "<prompt>"
```

**Example:**
```bash
scripts/firecrawl.sh extract "https://firecrawl.dev" "Extract pricing tiers with name, price, and features"
```

### Crawl Entire Site

```bash
scripts/firecrawl.sh crawl "<url>" [limit] [depth]
```

Recursive crawl with job polling. Returns full markdown for each page.

## Key Strengths

- **No output truncation** — Full content passes through for all commands
- **PDF support** — Parses PDFs natively (use parsers option for OCR on scanned docs)
- **Batch processing** — `batch-scrape` handles many URLs in parallel
- **JS rendering** — `waitFor` option for SPAs that need client-side rendering
- **Anti-bot bypass** — `"proxy":"stealth"` for Cloudflare-protected sites
- **Site mapping** — `map` discovers all URLs on a domain for targeted scraping

## Critical Rules

1. **Map before batch-scrape** — Use `map` to discover URLs, then `batch-scrape` the relevant ones
2. **Scrape for single pages** — Use `scrape` when you have one specific URL
3. **Use TinyFish for simple HTML fetching** — TinyFish returns more content for plain HTML pages
4. **Use Firecrawl for PDFs** — TinyFish cannot parse PDFs; Firecrawl handles them natively
5. **waitFor for SPAs** — Add `'{"waitFor":3000}'` for JS-heavy sites that load content dynamically
6. **Extract for structure** — Use `extract` when you need JSON, not markdown

## Resources

See `reference/troubleshooting.md` for error handling, configuration, and common issues.

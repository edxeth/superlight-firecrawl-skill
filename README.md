# Superlight Firecrawl Skill

Scrape and crawl web pages via the Firecrawl v2 REST API. A superlight agent skill for AI coding assistants — minimal tokens, maximum web data extraction. Supports multiple API keys with round-robin rotation and automatic 429 failover.

## Features

- **Web scraping** — Convert any URL to clean markdown, HTML, or structured JSON
- **Site crawling** — Recursively crawl entire websites or sections
- **URL discovery** — Map all URLs on a website instantly
- **Search + scrape** — Web search with automatic content extraction
- **Structured extraction** — Extract JSON data from pages using natural language prompts
- **JavaScript rendering** — Handle dynamic/JS-rendered content
- **Token-efficient** — Minimal context overhead with progressive disclosure
- **Multi-key rotation** — Round-robin distribution with automatic 429 failover

## Why Use This Over Firecrawl MCP?

| Aspect | MCP Server | This Skill |
|--------|------------|------------|
| Context cost | **~700+ tokens always**¹ | **~86 tokens always** + ~748 on-demand |
| Tool schemas | Always in context | None (progressive disclosure) |
| Setup | Requires MCP configuration | Drop-in skill directory |
| Dependencies | Node.js runtime | bash, curl, jq (Linux/macOS) |

¹ *Estimated from multi-tool MCP measurements (~14k tokens for 20 tools). [Source](https://scottspence.com/posts/optimising-mcp-server-context-usage-in-claude-code)*

Best for: Users who need web scraping on-demand without persistent context overhead.

## Token Budget

Uses Claude's [progressive disclosure](https://docs.anthropic.com/en/docs/agents-and-tools/agent-skills) architecture:

| Level | When Loaded | Content | Tokens |
|-------|-------------|---------|--------|
| **Metadata** | Always (startup) | Skill description | ~86 |
| **Instructions** | When triggered | SKILL.md protocol | ~748 |
| **Resources** | As needed | troubleshooting.md | ~817 |

*Token counts measured with [claudetokenizer.com](https://www.claudetokenizer.com/) (Claude Sonnet 4.5)*

## Installation

### Quick Install (Recommended)

```bash
npx skills add edxeth/superlight-firecrawl-skill
```

The installer will prompt you to select which agents to install to (Claude Code, Cursor, OpenCode, Codex, Antigravity, etc.).

### Manual Installation

Clone directly to your agent's skills directory:

```bash
# Claude Code
git clone https://github.com/edxeth/superlight-firecrawl-skill.git ~/.claude/skills/firecrawl

# OpenCode
git clone https://github.com/edxeth/superlight-firecrawl-skill.git ~/.opencode/skill/firecrawl
```

**Directory structure:**

```
firecrawl/
├── SKILL.md
├── reference/
│   └── troubleshooting.md
└── scripts/
    └── firecrawl.sh
```

## Usage

The skill triggers automatically when scraping or crawling websites:

```
"Scrape the content from this URL"
"Crawl the documentation site and extract all pages"
"Map all URLs on this website"
"Extract the pricing information from this page"
```

### Manual Invocation

```bash
# Scrape a single URL
./scripts/firecrawl.sh scrape "https://example.com"
./scripts/firecrawl.sh scrape "https://example.com" "html"

# Search web + scrape results
./scripts/firecrawl.sh search "firecrawl web scraping API" 5

# Map website URLs
./scripts/firecrawl.sh map "https://firecrawl.dev" 50
./scripts/firecrawl.sh map "https://docs.firecrawl.dev" 100 "api reference"

# Extract structured data
./scripts/firecrawl.sh extract "https://firecrawl.dev" "Extract pricing tiers"

# Crawl entire site
./scripts/firecrawl.sh crawl "https://docs.firecrawl.dev" 20 2
```

## API Endpoints

Uses Firecrawl v2 REST API:

| Endpoint | Purpose | Rate Limit (Standard) |
|----------|---------|----------------------|
| `POST /v2/scrape` | Scrape single URL | 500/min |
| `POST /v2/search` | Web search + scrape | 250/min |
| `POST /v2/map` | Discover site URLs | 500/min |
| `POST /v2/crawl` | Recursive crawl | 50/min |

## Configuration

API key is **required**.

```bash
# Single API key
export FIRECRAWL_API_KEY="fc-your-key-here"

# Multiple API keys for load distribution
export FIRECRAWL_API_KEY="fc-key1,fc-key2,fc-key3"
```

When multiple keys are provided (comma-separated), the script rotates through them in round-robin order, ensuring even distribution of requests. If a key hits rate limits (429), the script automatically fails over to the next key and retries, only failing after all keys are exhausted across multiple retry rounds.

Get an API key at [firecrawl.dev](https://firecrawl.dev/).

## Requirements

- **Platforms**: Linux, macOS
- **Dependencies**: bash, curl, jq

## Skill Metadata

```yaml
name: firecrawl
description: Scrapes and crawls web pages, converting them to clean markdown or structured JSON for LLM consumption. Use when needing to extract content from URLs, crawl entire websites, map site structure, search the web with scraping, or extract structured data from pages.
```

## License

MIT License

#!/bin/bash
# Firecrawl v2 REST API Client
# Endpoints: /v2/scrape, /v2/search, /v2/map, /v2/crawl, /v2/extract
# Docs: https://docs.firecrawl.dev/api-reference/v2-introduction

set -euo pipefail

readonly API_BASE="https://api.firecrawl.dev/v2"
readonly API_KEYS="${FIRECRAWL_API_KEY:-}"
readonly KEY_STATE_FILE="${TMPDIR:-/tmp}/.firecrawl-key-idx-${UID:-0}"
readonly KEY_LOCK_FILE="${TMPDIR:-/tmp}/.firecrawl-key-lock"
readonly MAX_RETRIES=3
readonly BASE_DELAY=1

get_key_count() {
    [[ -z "$API_KEYS" ]] && { echo 0; return; }
    IFS=',' read -ra keys <<< "$API_KEYS"
    echo ${#keys[@]}
}

select_next_api_key() {
    [[ -z "$API_KEYS" ]] && return
    
    IFS=',' read -ra keys <<< "$API_KEYS"
    local count=${#keys[@]}
    
    [[ $count -eq 1 ]] && { echo "${keys[0]}"; return; }
    
    local idx=0
    (
        flock -w 1 200 2>/dev/null || true
        [[ -f "$KEY_STATE_FILE" ]] && idx=$(cat "$KEY_STATE_FILE" 2>/dev/null || echo 0)
        local next_idx=$(( (idx + 1) % count ))
        local tmp_file="${KEY_STATE_FILE}.tmp.$$"
        echo "$next_idx" > "$tmp_file" && mv "$tmp_file" "$KEY_STATE_FILE"
    ) 200>"$KEY_LOCK_FILE"
    
    [[ -f "$KEY_STATE_FILE" ]] && idx=$(cat "$KEY_STATE_FILE" 2>/dev/null || echo 0)
    idx=$(( (idx + count - 1) % count ))
    echo "${keys[$idx]}"
}

# URL-encode a string (POSIX-compatible)
urlencode() {
    local string="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('''$string''', safe=''))" 2>/dev/null \
        || printf '%s' "$string" | jq -sRr @uri 2>/dev/null \
        || printf '%s' "$string"
}

do_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local key_count attempts_per_round total_attempts max_attempts round
    key_count=$(get_key_count)
    attempts_per_round=$((key_count > 1 ? key_count : 1))
    total_attempts=0
    max_attempts=$((attempts_per_round * MAX_RETRIES))
    round=0
    
    while [[ $total_attempts -lt $max_attempts ]]; do
        local api_key http_code response
        api_key=$(select_next_api_key)
        
        if [[ -z "$api_key" ]]; then
            echo "ERROR: FIRECRAWL_API_KEY not set. Get one at: https://firecrawl.dev/" >&2
            exit 1
        fi
        
        local -a curl_args=(-sS -w "%{http_code}" --max-time 60)
        curl_args+=(-H "Authorization: Bearer $api_key")
        curl_args+=(-H "Content-Type: application/json")
        
        if [[ "$method" == "POST" && -n "$data" ]]; then
            curl_args+=(-X POST -d "$data")
        fi
        
        response=$(curl "${curl_args[@]}" "${API_BASE}${endpoint}" 2>/dev/null) || true
        http_code="${response: -3}"
        response="${response%???}"
        
        case "$http_code" in
            200) echo "$response"; return 0 ;;
            429|408|500|502|503|504|000)
                total_attempts=$((total_attempts + 1))
                if [[ $((total_attempts % attempts_per_round)) -eq 0 ]]; then
                    round=$((round + 1))
                    local delay=$((BASE_DELAY * (2 ** (round - 1))))
                    [[ $delay -gt 16 ]] && delay=16
                    sleep "$delay"
                fi
                ;;
            401|402)
                total_attempts=$((total_attempts + 1))
                if [[ $key_count -gt 1 && $total_attempts -lt $max_attempts ]]; then
                    continue
                fi
                if [[ "$http_code" == "401" ]]; then
                    echo "ERROR: Invalid API key(s). Check FIRECRAWL_API_KEY." >&2
                else
                    echo "ERROR: Insufficient credits on all keys. Top up at https://firecrawl.dev/" >&2
                fi
                return 1
                ;;
            400)
                echo "ERROR: Bad request - $response" >&2
                return 1
                ;;
            *) 
                echo "ERROR: HTTP $http_code - $response" >&2
                return 1
                ;;
        esac
    done
    
    echo "ERROR: Rate limited on all keys after $MAX_RETRIES retries" >&2
    return 1
}

# Scrape a single URL
# API: POST /v2/scrape
cmd_scrape() {
    local url="${1:-}"
    local format="${2:-markdown}"
    
    if [[ -z "$url" ]]; then
        echo "Usage: firecrawl.sh scrape <url> [format]"
        echo "Formats: markdown (default), html, links, screenshot"
        echo "Example: firecrawl.sh scrape \"https://example.com\""
        exit 1
    fi
    
    local formats_array
    case "$format" in
        markdown) formats_array='["markdown"]' ;;
        html) formats_array='["html"]' ;;
        links) formats_array='["links"]' ;;
        screenshot) formats_array='[{"type":"screenshot","fullPage":true}]' ;;
        *) formats_array='["markdown"]' ;;
    esac
    
    local json_payload
    json_payload=$(jq -n \
        --arg url "$url" \
        --argjson formats "$formats_array" \
        '{
            url: $url,
            formats: $formats,
            onlyMainContent: true
        }'
    )
    
    local response
    if ! response=$(do_request "POST" "/scrape" "$json_payload"); then
        echo "ERROR: Scrape failed." >&2
        exit 1
    fi
    
    # Parse and output relevant content (truncated for token efficiency)
    echo "$response" | jq -r '
        if .success == true and .data then
            if .data.markdown then
                "## " + (.data.metadata.title // "Page Content") + "\n" +
                "URL: " + (.data.metadata.sourceURL // "unknown") + "\n\n" +
                (.data.markdown[:3000] // "")[:3000] +
                (if (.data.markdown | length) > 3000 then "\n\n[...truncated, " + ((.data.markdown | length) | tostring) + " chars total]" else "" end)
            elif .data.html then
                (.data.html[:3000] // "")[:3000] + "\n\n[...truncated]"
            elif .data.links then
                (.data.links[:30] | join("\n"))
            elif .data.screenshot then
                "Screenshot: " + .data.screenshot
            else
                (. | tostring)[:2000]
            end
        elif .error then
            "ERROR: " + .error
        else
            "ERROR: " + ((. | tostring)[:500])
        end
    ' 2>/dev/null || echo "$response"
}

# Search the web
# API: POST /v2/search
cmd_search() {
    local query="${1:-}"
    local limit="${2:-5}"
    
    if [[ -z "$query" ]]; then
        echo "Usage: firecrawl.sh search <query> [limit]"
        echo "Example: firecrawl.sh search \"firecrawl web scraping\" 5"
        exit 1
    fi
    
    local json_payload
    json_payload=$(jq -n \
        --arg query "$query" \
        --argjson limit "$limit" \
        '{
            query: $query,
            limit: $limit,
            scrapeOptions: {
                formats: ["markdown"],
                onlyMainContent: true
            }
        }'
    )
    
    local response
    if ! response=$(do_request "POST" "/search" "$json_payload"); then
        echo "ERROR: Search failed." >&2
        exit 1
    fi
    
    # Parse and output search results with scraped content
    echo "$response" | jq -r '
        if .success == true and .data then
            if (.data | type) == "array" then
                (.data[:5] | to_entries | map(
                    "## " + ((.key + 1) | tostring) + ". " + (.value.title // "No title") + "\n" +
                    "URL: " + .value.url + "\n\n" +
                    (.value.markdown[:1000] // .value.description // "")[:1000] + "...\n"
                ) | join("\n---\n"))
            elif .data.web then
                (.data.web[:5] | to_entries | map(
                    ((.key + 1) | tostring) + ". " + (.value.title // "No title") + "\n   " + .value.url + "\n   " + (.value.description // "")[:200]
                ) | join("\n\n"))
            else
                . | tostring
            end
        elif .error then
            "ERROR: " + .error
        else
            "No results found."
        end
    ' 2>/dev/null || echo "$response"
}

# Map a website (discover URLs)
# API: POST /v2/map
cmd_map() {
    local url="${1:-}"
    local limit="${2:-50}"
    local search="${3:-}"
    
    if [[ -z "$url" ]]; then
        echo "Usage: firecrawl.sh map <url> [limit] [search]"
        echo "Example: firecrawl.sh map \"https://firecrawl.dev\" 50"
        echo "Example: firecrawl.sh map \"https://docs.firecrawl.dev\" 100 \"api reference\""
        exit 1
    fi
    
    local json_payload
    if [[ -n "$search" ]]; then
        json_payload=$(jq -n \
            --arg url "$url" \
            --argjson limit "$limit" \
            --arg search "$search" \
            '{
                url: $url,
                limit: $limit,
                search: $search,
                includeSubdomains: true
            }'
        )
    else
        json_payload=$(jq -n \
            --arg url "$url" \
            --argjson limit "$limit" \
            '{
                url: $url,
                limit: $limit,
                includeSubdomains: true
            }'
        )
    fi
    
    local response
    if ! response=$(do_request "POST" "/map" "$json_payload"); then
        echo "ERROR: Map failed." >&2
        exit 1
    fi
    
    # Parse and output mapped URLs
    echo "$response" | jq -r '
        if .success == true and .links then
            "\(.links | length) URLs found:\n" +
            (.links[:30] | map(
                if type == "object" then
                    .url + (if .title then " [" + .title + "]" else "" end)
                else
                    .
                end
            ) | join("\n"))
        elif .error then
            "ERROR: " + .error
        else
            "No URLs found."
        end
    ' 2>/dev/null || echo "$response"
}

# Extract structured data
# API: POST /v2/scrape with JSON format
cmd_extract() {
    local url="${1:-}"
    local prompt="${2:-}"
    
    if [[ -z "$url" || -z "$prompt" ]]; then
        echo "Usage: firecrawl.sh extract <url> <prompt>"
        echo "Example: firecrawl.sh extract \"https://firecrawl.dev\" \"Extract company name and pricing\""
        exit 1
    fi
    
    local json_payload
    json_payload=$(jq -n \
        --arg url "$url" \
        --arg prompt "$prompt" \
        '{
            url: $url,
            formats: [{"type": "json", "prompt": $prompt}],
            onlyMainContent: false
        }'
    )
    
    local response
    if ! response=$(do_request "POST" "/scrape" "$json_payload"); then
        echo "ERROR: Extract failed." >&2
        exit 1
    fi
    
    # Return JSON data (truncated for token efficiency)
    echo "$response" | jq -r '
        if .success == true and .data.json then
            (.data.json | tojson)[:5000] +
            (if ((.data.json | tojson) | length) > 5000 then "\n[...truncated]" else "" end)
        elif .success == true and .data then
            (.data | tojson)[:5000]
        elif .error then
            "ERROR: " + .error
        else
            ((. | tostring)[:500])
        end
    ' 2>/dev/null || echo "$response"
}

# Crawl a website
# API: POST /v2/crawl
cmd_crawl() {
    local url="${1:-}"
    local limit="${2:-10}"
    local depth="${3:-2}"
    
    if [[ -z "$url" ]]; then
        echo "Usage: firecrawl.sh crawl <url> [limit] [depth]"
        echo "Example: firecrawl.sh crawl \"https://docs.firecrawl.dev\" 20 2"
        exit 1
    fi
    
    local json_payload
    json_payload=$(jq -n \
        --arg url "$url" \
        --argjson limit "$limit" \
        --argjson depth "$depth" \
        '{
            url: $url,
            limit: $limit,
            maxDiscoveryDepth: $depth,
            scrapeOptions: {
                formats: ["markdown"],
                onlyMainContent: true
            }
        }'
    )
    
    local response
    if ! response=$(do_request "POST" "/crawl" "$json_payload"); then
        echo "ERROR: Crawl failed." >&2
        exit 1
    fi
    
    # Crawl returns a job ID, we need to poll for results
    local job_id
    job_id=$(echo "$response" | jq -r '.id // empty')
    
    if [[ -z "$job_id" ]]; then
        echo "ERROR: No job ID returned - $response" >&2
        exit 1
    fi
    
    echo "Crawl started. Job ID: $job_id"
    echo "Polling for results..."
    
    # Poll for completion (max 60 seconds)
    local poll_count=0
    local max_polls=30
    while [[ $poll_count -lt $max_polls ]]; do
        sleep 2
        local status_response
        if ! status_response=$(do_request "GET" "/crawl/$job_id" ""); then
            echo "ERROR: Failed to get crawl status" >&2
            exit 1
        fi
        
        local status
        status=$(echo "$status_response" | jq -r '.status // "unknown"')
        
        case "$status" in
            completed)
                echo "$status_response" | jq -r '
                    if .data then
                        "Crawled \(.data | length) pages:\n" +
                        (.data[:10] | map(
                            "## " + (.metadata.title // "Page") + "\n" +
                            "URL: " + .metadata.sourceURL + "\n" +
                            (.markdown[:500] // "")[:500] + "...\n"
                        ) | join("\n---\n"))
                    else
                        "Crawl completed but no data returned."
                    end
                '
                return 0
                ;;
            failed)
                echo "ERROR: Crawl failed" >&2
                exit 1
                ;;
            scraping)
                local completed total
                completed=$(echo "$status_response" | jq -r '.completed // 0')
                total=$(echo "$status_response" | jq -r '.total // "?"')
                echo "Progress: $completed/$total pages..."
                ;;
        esac
        
        poll_count=$((poll_count + 1))
    done
    
    echo "Crawl still in progress. Job ID: $job_id"
    echo "Check status later or increase timeout."
}

# Main dispatch
case "${1:-}" in
    scrape)
        shift
        cmd_scrape "$@"
        ;;
    search)
        shift
        cmd_search "$@"
        ;;
    map)
        shift
        cmd_map "$@"
        ;;
    extract)
        shift
        cmd_extract "$@"
        ;;
    crawl)
        shift
        cmd_crawl "$@"
        ;;
    -h|--help|help)
        cat <<'EOF'
Firecrawl Web Scraping

Usage:
  firecrawl.sh scrape <url> [format]           Scrape a single URL
  firecrawl.sh search <query> [limit]          Search web + scrape results
  firecrawl.sh map <url> [limit] [search]      Discover all URLs on a site
  firecrawl.sh extract <url> <prompt>          Extract structured JSON data
  firecrawl.sh crawl <url> [limit] [depth]     Crawl entire site

Formats (for scrape):
  markdown (default), html, links, screenshot

Examples:
  firecrawl.sh scrape "https://example.com"
  firecrawl.sh scrape "https://example.com" "html"
  firecrawl.sh search "firecrawl web scraping API" 5
  firecrawl.sh map "https://firecrawl.dev" 50
  firecrawl.sh map "https://docs.firecrawl.dev" 100 "api reference"
  firecrawl.sh extract "https://firecrawl.dev" "Extract pricing tiers"
  firecrawl.sh crawl "https://docs.firecrawl.dev" 20 2

Environment:
  FIRECRAWL_API_KEY    API key(s) for Firecrawl (required)
                       Supports comma-separated keys for rotation
                       Get one at: https://firecrawl.dev/
EOF
        ;;
    *)
        echo "Usage: firecrawl.sh {scrape|search|map|extract|crawl} [args...]"
        echo "Run 'firecrawl.sh --help' for examples"
        exit 1
        ;;
esac

"""
External market-data and swap-quote integrations.

- DexScreener: free, no API key, used for token listings/prices/volume/mcap.
- 0x API v2: used to get a real swap quote + the calldata needed to execute
  it on-chain. Requires a free API key from https://0x.org/docs/api.
"""

import logging
import time

import requests

DEXSCREENER_BASE = "https://api.dexscreener.com"
ZEROX_BASE = "https://api.0x.org"

log = logging.getLogger(__name__)

# Simple in-memory caches. DexScreener's free tier rate-limits hard enough
# that firing many near-simultaneous search requests reliably triggers 429s
# (confirmed in production logs). The fixes here: cache for much longer so
# this expensive refresh runs rarely, use far fewer search terms so each
# refresh is a small burst instead of a large one, and — critically — never
# let a failed/rate-limited refresh overwrite good cached data with an
# empty result; fall back to the last good (even if stale) data instead.
_trending_cache = {}  # key: chain_id or "*"  -> (timestamp, data)
_TRENDING_TTL = 180  # seconds

_pair_cache = {}  # key: (chain_id, pair_address) -> (timestamp, data)
_PAIR_TTL = 20  # seconds


def search_tokens(query: str, limit: int = 30):
    """Search DexScreener for tokens/pairs matching a query (symbol or name)."""
    try:
        r = requests.get(
            f"{DEXSCREENER_BASE}/latest/dex/search",
            params={"q": query},
            timeout=8,
        )
        r.raise_for_status()
        pairs = r.json().get("pairs") or []
        return [_normalize_pair(p) for p in pairs[:limit]]
    except requests.RequestException as e:
        log.error("search_tokens(%r) failed: %s", query, e)
        return []


def get_trending(chain_id: str = None, limit: int = 300):
    """
    Discovery list for the homepage/ticker, cached for _TRENDING_TTL seconds
    per chain filter. On a failed/rate-limited refresh, falls back to the
    last good cached data (even if stale) rather than showing nothing.
    """
    cache_key = chain_id or "*"
    cached = _trending_cache.get(cache_key)
    if cached and (time.monotonic() - cached[0]) < _TRENDING_TTL:
        return cached[1]

    results = []

    # Bonus source: actively promoted/boosted tokens, when available.
    try:
        r = requests.get(f"{DEXSCREENER_BASE}/token-boosts/top/v1", timeout=8)
        r.raise_for_status()
        boosted = r.json() or []
        by_chain = {}
        for b in boosted[: limit * 2]:
            cid, addr = b.get("chainId"), b.get("tokenAddress")
            if cid and addr:
                by_chain.setdefault(cid, []).append(addr)
        for cid, addresses in by_chain.items():
            try:
                rr = requests.get(
                    f"{DEXSCREENER_BASE}/tokens/v1/{cid}/{','.join(addresses[:30])}",
                    timeout=8,
                )
                rr.raise_for_status()
                pairs = rr.json() or []
                results.extend(_normalize_pair(p) for p in pairs)
            except requests.RequestException as e:
                log.warning("token-boosts detail fetch failed for chain %s: %s", cid, e)
    except requests.RequestException as e:
        log.warning("token-boosts/top fetch failed (using search fallback only): %s", e)

    # Primary source: a wide set of search terms merged together. Caching
    # means this whole block only runs once every _TRENDING_TTL seconds
    # regardless of how many people are browsing, so we can afford more
    # terms than a live-every-request approach could — a small pause
    # between calls still avoids bursting DexScreener's rate limit.
    search_terms = (
        "pepe", "doge", "wif", "bonk", "shiba", "floki", "trump", "cat",
        "inu", "moon", "elon", "frog", "baby", "safe", "wojak", "chad",
        "based", "turbo", "ai", "meme", "dog", "pump", "rocket", "coin",
    )
    for i, term in enumerate(search_terms):
        if i > 0:
            time.sleep(0.3)
        results.extend(search_tokens(term, limit=25))

    if chain_id:
        results = [p for p in results if p["chain_id"] == chain_id]

    # De-duplicate by pair address, keep highest volume first.
    seen = set()
    deduped = []
    for p in sorted(results, key=lambda p: p.get("volume_24h") or 0, reverse=True):
        key = p.get("pair_address")
        if key and key in seen:
            continue
        seen.add(key)
        deduped.append(p)

    deduped = deduped[:limit]

    if deduped:
        _trending_cache[cache_key] = (time.monotonic(), deduped)
        return deduped

    # Refresh failed (likely rate-limited) — serve stale cached data rather
    # than wiping out good results with an empty list.
    if cached:
        log.warning("get_trending refresh failed, serving stale cache (chain_id=%r)", chain_id)
        return cached[1]

    log.error("get_trending produced zero results and no cache to fall back on (chain_id=%r)", chain_id)
    return []


def get_pair(chain_id: str, pair_address: str):
    cache_key = (chain_id, pair_address)
    cached = _pair_cache.get(cache_key)
    if cached and (time.monotonic() - cached[0]) < _PAIR_TTL:
        return cached[1]

    try:
        r = requests.get(
            f"{DEXSCREENER_BASE}/latest/dex/pairs/{chain_id}/{pair_address}", timeout=8
        )
        r.raise_for_status()
        pairs = r.json().get("pairs") or []
        result = _normalize_pair(pairs[0]) if pairs else None
    except Exception as e:  # noqa: BLE001 — deliberately broad: a malformed
        # response (unexpected shape, missing keys) should degrade the same
        # way a network failure does, not surface as a raw 500.
        log.error("get_pair(%r, %r) failed: %s", chain_id, pair_address, e)
        return cached[1] if cached else None

    _pair_cache[cache_key] = (time.monotonic(), result)
    return result


def _normalize_pair(p: dict):
    return {
        "chain_id": p.get("chainId"),
        "dex_id": p.get("dexId"),
        "pair_address": p.get("pairAddress"),
        "base_symbol": p.get("baseToken", {}).get("symbol"),
        "base_name": p.get("baseToken", {}).get("name"),
        "base_address": p.get("baseToken", {}).get("address"),
        "icon": (p.get("info") or {}).get("imageUrl"),
        "price_usd": float(p["priceUsd"]) if p.get("priceUsd") else None,
        "price_change_24h": (p.get("priceChange") or {}).get("h24"),
        "volume_24h": (p.get("volume") or {}).get("h24"),
        "liquidity_usd": (p.get("liquidity") or {}).get("usd"),
        "mcap": p.get("marketCap") or p.get("fdv"),
        "url": p.get("url"),
    }


class ZeroXError(Exception):
    pass


def get_swap_quote(api_key, chain_id, sell_token, buy_token, sell_amount, taker_address):
    """
    Get a firm swap quote (includes the transaction calldata to submit).
    Amounts are in the token's smallest unit (wei for 18-decimal tokens).
    """
    if not api_key:
        raise ZeroXError("ZEROX_API_KEY is not configured.")

    headers = {"0x-api-key": api_key, "0x-version": "v2"}
    params = {
        "chainId": chain_id,
        "sellToken": sell_token,
        "buyToken": buy_token,
        "sellAmount": str(sell_amount),
        "taker": taker_address,
    }
    r = requests.get(f"{ZEROX_BASE}/swap/permit2/quote", params=params, headers=headers, timeout=15)
    if r.status_code != 200:
        raise ZeroXError(f"0x API error {r.status_code}: {r.text[:300]}")
    return r.json()


def get_swap_price(api_key, chain_id, sell_token, buy_token, sell_amount):
    """Indicative price (no calldata) — cheap to call for live UI updates."""
    if not api_key:
        raise ZeroXError("ZEROX_API_KEY is not configured.")

    headers = {"0x-api-key": api_key, "0x-version": "v2"}
    params = {
        "chainId": chain_id,
        "sellToken": sell_token,
        "buyToken": buy_token,
        "sellAmount": str(sell_amount),
    }
    r = requests.get(f"{ZEROX_BASE}/swap/permit2/price", params=params, headers=headers, timeout=15)
    if r.status_code != 200:
        raise ZeroXError(f"0x API error {r.status_code}: {r.text[:300]}")
    return r.json()

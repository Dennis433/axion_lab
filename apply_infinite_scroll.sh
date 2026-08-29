#!/usr/bin/env bash
set -e
echo "Applying infinite scroll + wider token pool..."

cat > 'app/dex_api.py' << 'MEMELAB_EOF'
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
MEMELAB_EOF

cat > 'app/static/js/app.js' << 'MEMELAB_EOF'
/* MemeDex frontend
 * Written to avoid the "slow and glitchy" symptoms of the original site:
 *  - every network call is debounced and cancels its own stale predecessor
 *    (AbortController) so fast typing/clicking can't pile up requests
 *  - table re-renders build one HTML string and set it once, instead of
 *    incremental DOM mutation
 *  - polling intervals are cleared on page unload
 */

const MemeDex = (() => {
  let searchAbort = null;
  let pollTimer = null;

  function debounce(fn, wait) {
    let t;
    return (...args) => {
      clearTimeout(t);
      t = setTimeout(() => fn(...args), wait);
    };
  }

  function fmtNumber(n) {
    if (n === null || n === undefined) return "--";
    const num = Number(n);
    if (Number.isNaN(num)) return "--";
    if (num >= 1e9) return "$" + (num / 1e9).toFixed(2) + "B";
    if (num >= 1e6) return "$" + (num / 1e6).toFixed(2) + "M";
    if (num >= 1e3) return "$" + (num / 1e3).toFixed(1) + "K";
    return "$" + num.toFixed(2);
  }

  function fmtChange(n) {
    if (n === null || n === undefined) return { text: "--", cls: "" };
    const num = Number(n);
    const cls = num >= 0 ? "change-up" : "change-down";
    const arrow = num >= 0 ? "↑" : "↓";
    return { text: `${arrow} ${Math.abs(num).toFixed(1)}%`, cls };
  }

  function sparklineSvg(up) {
    // Lightweight decorative sparkline (no extra network call per row).
    const color = up ? "#00d9a3" : "#ff2d6b";
    const points = up
      ? "0,20 15,18 30,14 45,16 60,8 75,10 90,4"
      : "0,6 15,9 30,7 45,12 60,10 75,18 90,20";
    return `<svg class="sparkline" viewBox="0 0 90 28"><polyline points="${points}" fill="none" stroke="${color}" stroke-width="2"/></svg>`;
  }

  function tokenIconUrl(t) {
    if (t.icon) return t.icon;
    // No logo on DexScreener for this token — generate a deterministic
    // identicon instead, so every row always shows a picture.
    const seed = encodeURIComponent(t.base_address || t.base_symbol || "token");
    return `https://api.dicebear.com/7.x/identicon/svg?seed=${seed}&backgroundColor=17171c`;
  }

  const PAGE_SIZE = 25;
  let allTokens = [];
  let renderedCount = 0;

  function buildRowsHtml(tokens) {
    return tokens
      .map((t) => {
        const change = fmtChange(t.price_change_24h);
        const icon = tokenIconUrl(t);
        return `
          <tr data-chain="${t.chain_id || ""}" data-pair="${t.pair_address || ""}">
            <td>
              <div class="coin-cell">
                <img class="coin-icon" src="${icon}" loading="lazy" alt="" onerror="this.style.visibility='hidden'">
                <div>
                  <div class="coin-symbol" data-text="${t.base_symbol || "?"}">${t.base_symbol || "?"}</div>
                  <div class="coin-name">${t.base_name || ""}</div>
                </div>
              </div>
            </td>
            <td class="mcap-cell">
              ${fmtNumber(t.mcap)}
              <div class="${change.cls}">${change.text}</div>
            </td>
            <td class="vol-cell">${fmtNumber(t.volume_24h)}</td>
            <td>${sparklineSvg(Number(t.price_change_24h) >= 0)}</td>
          </tr>`;
      })
      .join("");
  }

  function wireRowClicks(rows) {
    rows.forEach((row) => {
      row.addEventListener("click", () => {
        const chain = row.getAttribute("data-chain");
        const pair = row.getAttribute("data-pair");
        if (chain && pair) showTokenModal(chain, pair);
      });
    });
  }

  function renderRows(tokens) {
    // Fresh result set (new search/filter) — reset pagination state.
    allTokens = tokens;
    renderedCount = 0;

    const tbody = document.getElementById("coin-rows");
    if (!tbody) return;

    if (!tokens.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="empty-row">No tokens found.</td></tr>`;
      return;
    }

    tbody.innerHTML = "";
    appendNextPage();
  }

  function appendNextPage() {
    const tbody = document.getElementById("coin-rows");
    if (!tbody || renderedCount >= allTokens.length) return;

    const nextBatch = allTokens.slice(renderedCount, renderedCount + PAGE_SIZE);
    const html = buildRowsHtml(nextBatch);

    tbody.insertAdjacentHTML("beforeend", html);
    wireRowClicks([...tbody.querySelectorAll("tr[data-pair]")].slice(-nextBatch.length));
    renderedCount += nextBatch.length;

    updateScrollStatus();
  }

  function updateScrollStatus() {
    const statusEl = document.getElementById("scroll-status");
    if (!statusEl) return;
    if (renderedCount >= allTokens.length && allTokens.length > 0) {
      statusEl.textContent = `Showing all ${allTokens.length} tokens`;
    } else if (allTokens.length > 0) {
      statusEl.textContent = `Showing ${renderedCount} of ${allTokens.length} — scroll for more`;
    } else {
      statusEl.textContent = "";
    }
  }

  function initInfiniteScroll() {
    const sentinel = document.getElementById("scroll-sentinel");
    if (!sentinel || typeof IntersectionObserver === "undefined") return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) appendNextPage();
      },
      { rootMargin: "400px" }
    );
    observer.observe(sentinel);
  }

  async function showTokenModal(chainId, pairAddress) {
    const modalEl = document.getElementById("token-modal");
    if (!modalEl || typeof bootstrap === "undefined") return;

    const modal = bootstrap.Modal.getOrCreateInstance(modalEl);
    const loadingEl = document.getElementById("tm-loading");
    const detailsEl = document.getElementById("tm-details");
    const iconEl = document.getElementById("tm-icon");

    // Reset to loading state each time it opens.
    loadingEl.classList.remove("d-none");
    detailsEl.classList.add("d-none");
    document.getElementById("tm-symbol").textContent = "—";
    document.getElementById("tm-name").textContent = "";
    iconEl.style.display = "none";
    modal.show();

    try {
      const res = await fetch(`/api/pair/${encodeURIComponent(chainId)}/${encodeURIComponent(pairAddress)}`);
      if (!res.ok) {
        console.error(`MemeDex: /api/pair returned ${res.status}`);
        loadingEl.textContent = "Couldn't load this token right now.";
        return;
      }
      const t = await res.json();
      const change = fmtChange(t.price_change_24h);

      document.getElementById("tm-symbol").textContent = t.base_symbol || "?";
      document.getElementById("tm-name").textContent = t.base_name || "";
      iconEl.src = tokenIconUrl(t);
      iconEl.style.display = "block";
      document.getElementById("tm-price").textContent = t.price_usd ? `$${Number(t.price_usd).toFixed(6)}` : "—";
      document.getElementById("tm-mcap").textContent = fmtNumber(t.mcap);
      document.getElementById("tm-vol").textContent = fmtNumber(t.volume_24h);
      document.getElementById("tm-liq").textContent = fmtNumber(t.liquidity_usd);
      document.getElementById("tm-change").innerHTML = `<span class="${change.cls}">${change.text}</span>`;
      document.getElementById("tm-dex").textContent = t.dex_id || "—";
      document.getElementById("tm-address").textContent = t.base_address || "—";

      const tradeLink = document.getElementById("tm-trade-link");
      tradeLink.href = `/trade?chain=${encodeURIComponent(chainId)}&token=${encodeURIComponent(t.base_address || "")}`;

      loadingEl.classList.add("d-none");
      detailsEl.classList.remove("d-none");
    } catch (err) {
      console.error("MemeDex: showTokenModal failed", err);
      loadingEl.textContent = "Couldn't load this token right now.";
    }
  }

  const CHAIN_LABELS = {
    ethereum: "Ethereum", base: "Base", bsc: "BNB Chain", polygon: "Polygon",
    arbitrum: "Arbitrum", optimism: "Optimism", solana: "Solana",
    avalanche: "Avalanche", fantom: "Fantom", tron: "Tron",
  };

  function chainLabel(id) {
    return CHAIN_LABELS[id] || (id.charAt(0).toUpperCase() + id.slice(1));
  }

  function updateChainChips(tokens, activeChain, onSelect) {
    const row = document.getElementById("filter-row");
    if (!row) return;

    // Only ever show chips for chains that actually have tokens right now —
    // no empty "Arbitrum" chip if nothing came back for it, and Solana (or
    // any other chain DexScreener returns) shows up automatically.
    const seen = new Set();
    tokens.forEach((t) => t.chain_id && seen.add(t.chain_id));
    const chains = [...seen].sort();

    // Preserve the static "All chains" and "High vol" buttons; rebuild only
    // the dynamic per-chain chips between them.
    row.querySelectorAll(".chip[data-chain]:not([data-chain=''])").forEach((el) => el.remove());
    const allChip = row.querySelector('.chip[data-chain=""]');

    chains.forEach((id) => {
      const btn = document.createElement("button");
      btn.className = "chip" + (id === activeChain ? " chip-active" : "");
      btn.dataset.chain = id;
      btn.textContent = chainLabel(id);
      btn.addEventListener("click", () => onSelect(id, btn));
      allChip.insertAdjacentElement("afterend", btn);
    });
  }

  function initHomepage() {
    let activeChain = "";
    initInfiniteScroll();

    function setActiveChain(chain) {
      activeChain = chain;
      document.querySelectorAll(".chip[data-chain]").forEach((c) => {
        c.classList.toggle("chip-active", c.getAttribute("data-chain") === chain);
      });
    }

    async function load() {
      const tbody = document.getElementById("coin-rows");
      if (searchAbort) searchAbort.abort();
      searchAbort = new AbortController();
      if (tbody) tbody.innerHTML = `<tr><td colspan="4" class="loading-row">Loading tokens…</td></tr>`;

      const params = new URLSearchParams();
      const q = currentQuery();
      if (q) params.set("q", q);
      if (activeChain) params.set("chain", activeChain);

      try {
        const res = await fetch(`/api/tokens?${params.toString()}`, { signal: searchAbort.signal });
        if (!res.ok) {
          console.error(`MemeDex: /api/tokens returned ${res.status}`);
          if (tbody) tbody.innerHTML = `<tr><td colspan="4" class="empty-row">Server error loading tokens.</td></tr>`;
          return;
        }
        const data = await res.json();
        renderRows(data.tokens || []);

        // Chain chips are only built from an *unfiltered* fetch, so we know
        // the full set of chains actually present — not just the one
        // currently selected.
        if (!activeChain) {
          updateChainChips(data.tokens || [], activeChain, (id, btnEl) => {
            setActiveChain(id);
            load();
          });
        }
      } catch (err) {
        if (err.name !== "AbortError") {
          console.error("MemeDex: fetchTokens failed", err);
          if (tbody) tbody.innerHTML = `<tr><td colspan="4" class="empty-row">Couldn't load tokens right now.</td></tr>`;
        }
      }
    }

    function currentQuery() {
      const el = document.getElementById("global-search");
      return el ? el.value.trim() : "";
    }

    load();
    pollTimer = setInterval(load, 20000);
    window.addEventListener("beforeunload", () => clearInterval(pollTimer));

    const searchInput = document.getElementById("global-search");
    const debouncedSearch = debounce(() => load(), 350);
    if (searchInput) {
      searchInput.addEventListener("input", debouncedSearch);
    }

    document.getElementById("filter-row").addEventListener("click", (e) => {
      const chip = e.target.closest(".chip[data-chain='']");
      if (chip) {
        setActiveChain("");
        load();
      }
    });
  }

  function initWalletPage() {
    function wireCopyButton(buttonId, confirmId) {
      const btn = document.getElementById(buttonId);
      const confirmEl = document.getElementById(confirmId);
      if (!btn) return;
      btn.addEventListener("click", async () => {
        const address = btn.getAttribute("data-address");
        try {
          await navigator.clipboard.writeText(address);
        } catch {
          const tmp = document.createElement("textarea");
          tmp.value = address;
          document.body.appendChild(tmp);
          tmp.select();
          document.execCommand("copy");
          document.body.removeChild(tmp);
        }
        if (confirmEl) {
          confirmEl.classList.add("show");
          setTimeout(() => confirmEl.classList.remove("show"), 1800);
        }
      });
    }

    wireCopyButton("copy-address", "copy-confirm");
    wireCopyButton("copy-solana-address", "copy-solana-confirm");

    fetch("/api/wallet/balance")
      .then((r) => r.json())
      .then((data) => {
        if (data.balances) {
          Object.entries(data.balances).forEach(([chainKey, info]) => {
            const el = document.querySelector(`[data-balance-for="${chainKey}"]`);
            if (el) {
              const bal = info.native_balance;
              el.textContent = bal !== null && bal !== undefined
                ? `${Number(bal).toFixed(4)} ${info.native_symbol}`
                : `0 ${info.native_symbol}`;
            }
          });
        }
        const solEl = document.querySelector('[data-balance-for="solana"]');
        if (solEl) {
          const bal = data.solana_balance;
          solEl.textContent = bal !== null && bal !== undefined ? `${Number(bal).toFixed(4)} SOL` : "0 SOL";
        }
      })
      .catch(() => {});
  }

  function initTradePage() {
    let currentQuote = null;
    let kind = "buy";

    // Prefill from a "Trade this token" link (?chain=...&token=...).
    const params = new URLSearchParams(window.location.search);
    const prefChain = params.get("chain");
    const prefToken = params.get("token");
    if (prefChain) {
      const chainSelect = document.getElementById("trade-chain");
      if (chainSelect && [...chainSelect.options].some((o) => o.value === prefChain)) {
        chainSelect.value = prefChain;
      }
    }
    if (prefToken) {
      const tokenInput = document.getElementById("trade-token");
      if (tokenInput) tokenInput.value = prefToken;
    }

    document.querySelectorAll(".trade-tab").forEach((tab) => {
      tab.addEventListener("click", () => {
        document.querySelectorAll(".trade-tab").forEach((t) => t.classList.remove("trade-tab-active"));
        tab.classList.add("trade-tab-active");
        kind = tab.getAttribute("data-kind");
      });
    });

    const statusEl = document.getElementById("trade-status");
    const quoteBox = document.getElementById("quote-box");

    document.getElementById("get-quote").addEventListener("click", async () => {
      const chain = document.getElementById("trade-chain").value;
      const token = document.getElementById("trade-token").value.trim();
      const amount = document.getElementById("trade-amount").value.trim();

      if (!token || !amount) {
        statusEl.textContent = "Enter a token address and amount first.";
        return;
      }

      statusEl.textContent = "Fetching quote…";
      quoteBox.classList.add("hidden");

      const NATIVE = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
      const sellToken = kind === "buy" ? NATIVE : token;
      const buyToken = kind === "buy" ? token : NATIVE;
      // NOTE: amount here should already be converted to the token's smallest
      // unit before calling the API in a production build (18 decimals for
      // most ERC-20s / native ETH — fetch actual decimals for arbitrary
      // tokens rather than assuming 18).
      const sellAmount = BigInt(Math.floor(parseFloat(amount) * 1e18)).toString();

      try {
        const res = await fetch("/api/swap/quote", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ chain, sell_token: sellToken, buy_token: buyToken, sell_amount: sellAmount }),
        });
        const data = await res.json();
        if (data.error) {
          statusEl.textContent = data.error;
          return;
        }
        currentQuote = data;
        document.getElementById("quote-buy-amount").textContent = data.buyAmount || "—";
        document.getElementById("quote-impact").textContent =
          data.priceImpact ? `${(Number(data.priceImpact) * 100).toFixed(2)}%` : "—";
        quoteBox.classList.remove("hidden");
        statusEl.textContent = "";
      } catch {
        statusEl.textContent = "Couldn't fetch a quote right now.";
      }
    });

    document.getElementById("confirm-swap").addEventListener("click", async () => {
      if (!currentQuote) return;
      const chain = document.getElementById("trade-chain").value;
      statusEl.textContent = "Submitting transaction…";

      try {
        const res = await fetch("/api/swap/execute", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ chain, kind, quote: currentQuote }),
        });
        const data = await res.json();
        if (data.error) {
          statusEl.textContent = data.error;
          return;
        }
        statusEl.innerHTML = `Submitted: <a href="${data.explorer}" target="_blank" rel="noopener">${data.tx_hash.slice(0, 10)}…</a>`;
      } catch {
        statusEl.textContent = "Swap failed to submit.";
      }
    });
  }

  function initChatBubble() {
    const fab = document.getElementById("chat-fab");
    const popover = document.getElementById("chat-popover");
    if (!fab || !popover) return;
    fab.addEventListener("click", () => popover.classList.toggle("open"));
    document.addEventListener("click", (e) => {
      if (!popover.contains(e.target) && e.target !== fab) popover.classList.remove("open");
    });
  }

  async function initTicker() {
    const track = document.getElementById("ticker-track");
    if (!track) return;

    async function refresh() {
      try {
        const res = await fetch("/api/tokens");
        if (!res.ok) {
          console.error(`MemeDex: ticker /api/tokens returned ${res.status}`);
          return;
        }
        const data = await res.json();
        const items = (data.tokens || []).slice(0, 15);
        if (!items.length) return;

        const html = items
          .map((t) => {
            const change = fmtChange(t.price_change_24h);
            return `<span class="ticker-item"><span class="ti-symbol">${t.base_symbol || "?"}</span> ${fmtNumber(t.mcap)} <span class="${change.cls}">${change.text}</span></span>`;
          })
          .join("");

        // Duplicate content so the marquee loop (translateX -50%) is seamless.
        track.innerHTML = html + html;
      } catch (err) {
        console.error("MemeDex: ticker refresh failed", err);
        // Leave existing ticker content in place rather than showing an error strip.
      }
    }

    refresh();
    const timer = setInterval(refresh, 30000);
    window.addEventListener("beforeunload", () => clearInterval(timer));
  }

  document.addEventListener("DOMContentLoaded", () => {
    initChatBubble();
    initTicker();
  });

  return { initHomepage, initWalletPage, initTradePage };
})();
MEMELAB_EOF

cat > 'app/templates/index.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}MemeDex — Live Meme Coin Tracker{% endblock %}
{% block content %}

<section class="hero">
  <div class="filter-row" id="filter-row">
    <button class="chip chip-active" data-chain="">All chains</button>
    <button class="chip chip-vol" id="highvol-toggle"><span class="dot"></span> High vol</button>
  </div>

  <div class="table-wrap">
    <table class="coin-table">
      <thead>
        <tr>
          <th class="col-coin">COIN <span class="sort">↕</span></th>
          <th class="col-mcap">MCAP <span class="sort">↕</span></th>
          <th class="col-vol">24H VOL</th>
          <th class="col-chart">CHART</th>
        </tr>
      </thead>
      <tbody id="coin-rows">
        <tr><td colspan="4" class="loading-row">Loading tokens…</td></tr>
      </tbody>
    </table>
  </div>
  <div id="scroll-sentinel" style="height: 1px;"></div>
  <div id="scroll-status" class="scroll-status"></div>
</section>

{% endblock %}

{% block scripts %}
<script>
  MemeDex.initHomepage();
</script>
{% endblock %}
MEMELAB_EOF

cat > 'app/static/css/style.css' << 'MEMELAB_EOF'
/* Fonts are loaded via <link> tags in base.html (non-blocking, more resilient
   than a CSS @import, and the page still renders correctly with the fallback
   fonts below even if the Google Fonts request fails). */

:root {
  --ink: #0d0d0f;
  --panel: #17171c;
  --panel-raised: #1f1f26;
  --hairline: #2c2c35;
  --signal: #00d9a3;
  --signal-dim: rgba(0, 217, 163, 0.14);
  --pulse: #ff2d6b;
  --pulse-dim: rgba(255, 45, 107, 0.14);
  --brand: #ff5a1f;
  --brand-dim: rgba(255, 90, 31, 0.16);
  --paper: #f2f1ee;
  --dim: #8a8a93;
  --radius-sm: 4px;
  --radius-md: 8px;
  --font-display: "Syne", sans-serif;
  --font-mono: "JetBrains Mono", ui-monospace, monospace;
  --font-body: "Manrope", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

* { box-sizing: border-box; }

html, body {
  margin: 0;
  background: var(--ink);
  color: var(--paper);
  font-family: var(--font-body);
  -webkit-font-smoothing: antialiased;
}

a { color: inherit; text-decoration: none; }

::selection { background: var(--brand); color: var(--ink); }

/* focus visibility, kept even though we style buttons custom */
button:focus-visible, a:focus-visible, input:focus-visible, select:focus-visible {
  outline: 2px solid var(--brand);
  outline-offset: 2px;
}

/* ---------- Topbar ---------- */
.topbar {
  display: flex;
  align-items: center;
  gap: 20px;
  padding: 14px 24px;
  border-bottom: 1px solid var(--hairline);
  position: sticky;
  top: 0;
  background: rgba(11, 10, 8, 0.94);
  backdrop-filter: blur(8px);
  z-index: 20;
}

.brand {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: 16px;
  letter-spacing: 0.02em;
  color: var(--brand);
  display: flex;
  align-items: center;
  gap: 7px;
  white-space: nowrap;
}
.brand-mark { font-size: 13px; }

.searchbar {
  flex: 1;
  max-width: 420px;
  display: flex;
  align-items: center;
  gap: 8px;
  background: var(--panel);
  border: 1px solid var(--hairline);
  border-radius: var(--radius-sm);
  padding: 8px 14px;
  color: var(--dim);
}
.searchbar input {
  background: transparent;
  border: none;
  outline: none;
  color: var(--paper);
  width: 100%;
  font-size: 14px;
  font-family: var(--font-mono);
}

.topnav { display: flex; align-items: center; gap: 16px; margin-left: auto; }
.topnav a:not(.btn-outline):not(.btn-solid) {
  color: var(--dim);
  font-size: 13px;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.06em;
}
.topnav a:not(.btn-outline):not(.btn-solid):hover { color: var(--paper); }

.btn-outline, .btn-solid {
  padding: 9px 18px;
  border-radius: var(--radius-sm);
  font-weight: 600;
  font-size: 13px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border: 1px solid var(--brand);
  cursor: pointer;
  font-family: var(--font-body);
  position: relative;
}
.btn-outline { background: transparent; color: var(--brand); }
.btn-outline:hover { background: var(--brand-dim); }
.btn-solid { background: var(--brand); color: var(--ink); border: 1px solid var(--brand); }
.btn-solid:hover { filter: brightness(1.08); }
.btn-full { width: 100%; margin-top: 8px; }

/* corner-notch accent: a small design signature on primary buttons */
.btn-solid::after {
  content: "";
  position: absolute;
  top: 0; right: 0;
  border-width: 0 9px 9px 0;
  border-style: solid;
  border-color: transparent var(--ink) transparent transparent;
  opacity: 0.25;
}

/* ---------- Ticker tape (signature element) ---------- */
.ticker-tape {
  border-bottom: 1px solid var(--hairline);
  background: var(--panel);
  overflow: hidden;
  white-space: nowrap;
  position: relative;
}
.ticker-tape::before, .ticker-tape::after {
  content: "";
  position: absolute;
  top: 0; bottom: 0;
  width: 40px;
  z-index: 2;
  pointer-events: none;
}
.ticker-tape::before { left: 0; background: linear-gradient(90deg, var(--panel), transparent); }
.ticker-tape::after { right: 0; background: linear-gradient(-90deg, var(--panel), transparent); }

.ticker-track {
  display: inline-flex;
  align-items: center;
  gap: 28px;
  padding: 9px 20px;
  font-family: var(--font-mono);
  font-size: 12.5px;
  animation: ticker-scroll 38s linear infinite;
  will-change: transform;
}
.ticker-item { display: inline-flex; align-items: center; gap: 7px; color: var(--dim); }
.ticker-item .ti-symbol { color: var(--paper); font-weight: 600; }
.ticker-up { color: var(--signal); }
.ticker-down { color: var(--pulse); }

@keyframes ticker-scroll {
  from { transform: translateX(0); }
  to { transform: translateX(-50%); }
}

@media (prefers-reduced-motion: reduce) {
  .ticker-track { animation: none; overflow-x: auto; }
}

/* ---------- Flash messages ---------- */
.flash-stack { max-width: 1100px; margin: 12px auto 0; padding: 0 24px; }
.flash {
  padding: 10px 16px; border-radius: var(--radius-sm); margin-bottom: 8px;
  font-size: 13px; font-family: var(--font-mono); border: 1px solid;
}
.flash-success { background: var(--brand-dim); color: var(--brand); border-color: rgba(255,90,31,.35); }
.flash-error { background: var(--pulse-dim); color: var(--pulse); border-color: rgba(255,45,107,.35); }

/* ---------- Hero / filters ---------- */
.hero { max-width: 1100px; margin: 20px auto; padding: 0 24px; }
.filter-row { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 16px; }
.chip {
  background: var(--panel);
  border: 1px solid var(--hairline);
  color: var(--dim);
  padding: 7px 14px;
  border-radius: var(--radius-sm);
  font-size: 12px;
  font-family: var(--font-mono);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  cursor: pointer;
}
.chip:hover { border-color: var(--brand); }
.chip-active { color: var(--brand); border-color: var(--brand); background: var(--brand-dim); }
.chip-vol { display: flex; align-items: center; gap: 6px; }
.chip-vol .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--pulse); display: inline-block; }

/* ---------- Coin table ---------- */
.table-wrap {
  background: var(--panel);
  border: 1px solid var(--hairline);
  border-radius: var(--radius-md);
  overflow: hidden;
}
.coin-table { width: 100%; border-collapse: collapse; }
.coin-table th {
  text-align: left;
  font-size: 10.5px;
  letter-spacing: .08em;
  color: var(--dim);
  padding: 13px 18px;
  border-bottom: 1px solid var(--hairline);
  font-weight: 600;
  font-family: var(--font-mono);
  text-transform: uppercase;
}
.sort { opacity: .5; font-size: 10px; }
.coin-table td { padding: 13px 18px; border-bottom: 1px solid var(--hairline); vertical-align: middle; }
.coin-table tr:last-child td { border-bottom: none; }
.coin-table tbody tr { cursor: pointer; transition: background .12s; }
.coin-table tbody tr:hover { background: rgba(255,90,31,0.06); }

.coin-cell { display: flex; align-items: center; gap: 12px; }
.coin-icon {
  width: 32px; height: 32px; border-radius: var(--radius-sm);
  background: var(--hairline); object-fit: cover; flex-shrink: 0;
}
.coin-symbol {
  font-weight: 700; font-size: 13.5px; font-family: var(--font-mono);
  position: relative; display: inline-block;
}
.coin-name { font-size: 12px; color: var(--dim); margin-top: 1px; }

/* one-shot RGB-split glitch flicker on hover — intentional, restrained */
.coin-table tbody tr:hover .coin-symbol::before,
.coin-table tbody tr:hover .coin-symbol::after {
  content: attr(data-text);
  position: absolute;
  left: 0; top: 0;
  width: 100%;
  overflow: hidden;
  animation: glitch-flicker 0.35s steps(2, end) 1;
}
.coin-table tbody tr:hover .coin-symbol::before { color: var(--pulse); clip-path: inset(0 0 55% 0); animation-delay: 0.02s; }
.coin-table tbody tr:hover .coin-symbol::after { color: var(--signal); clip-path: inset(55% 0 0 0); animation-delay: 0.05s; }
@keyframes glitch-flicker {
  0% { transform: translate(0, 0); opacity: 0.9; }
  50% { transform: translate(-1.5px, 0.5px); opacity: 0.6; }
  100% { transform: translate(0, 0); opacity: 0; }
}
@media (prefers-reduced-motion: reduce) {
  .coin-table tbody tr:hover .coin-symbol::before,
  .coin-table tbody tr:hover .coin-symbol::after { display: none; }
}

.mcap-cell { font-weight: 600; font-family: var(--font-mono); }
.change-up { color: var(--signal); font-size: 11.5px; font-family: var(--font-mono); }
.change-down { color: var(--pulse); font-size: 11.5px; font-family: var(--font-mono); }
.vol-cell { color: var(--dim); font-size: 13px; font-family: var(--font-mono); }
.loading-row, .empty-row { text-align: center; color: var(--dim); padding: 40px 0 !important; font-family: var(--font-mono); }

.sparkline { width: 90px; height: 26px; display: block; }

.scroll-status {
  text-align: center;
  color: var(--dim);
  font-family: var(--font-mono);
  font-size: 12px;
  padding: 16px 0;
}

/* ---------- Wallet page ---------- */
.wallet-page { max-width: 760px; margin: 32px auto; padding: 0 24px; }
.wallet-page h1 { font-family: var(--font-display); font-size: 22px; margin-bottom: 6px; }
.sub { color: var(--dim); font-size: 13.5px; margin-bottom: 24px; line-height: 1.5; }

.address-card {
  background: var(--panel);
  border: 1px solid var(--hairline);
  border-left: 2px solid var(--brand);
  border-radius: var(--radius-md);
  padding: 20px;
  margin-bottom: 24px;
}
.address-label {
  font-size: 11px; color: var(--dim); margin-bottom: 8px;
  text-transform: uppercase; letter-spacing: 0.08em; font-family: var(--font-mono);
}
.address-row { display: flex; align-items: center; gap: 10px; }
.address-row code {
  flex: 1;
  font-family: var(--font-mono);
  font-size: 13.5px;
  background: var(--ink);
  padding: 10px 14px;
  border-radius: var(--radius-sm);
  border: 1px solid var(--hairline);
  overflow-wrap: anywhere;
}
.copy-btn {
  background: var(--brand);
  color: var(--ink);
  border: none;
  padding: 10px 18px;
  border-radius: var(--radius-sm);
  font-weight: 700;
  font-size: 12.5px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  cursor: pointer;
  white-space: nowrap;
}
.copy-btn:hover { filter: brightness(1.08); }
.copy-confirm { opacity: 0; color: var(--brand); font-size: 12.5px; margin-top: 8px; transition: opacity .2s; font-family: var(--font-mono); }
.copy-confirm.show { opacity: 1; }

.chain-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; }
.chain-card { background: var(--panel); border: 1px solid var(--hairline); border-radius: var(--radius-sm); padding: 16px; }
.chain-card-top { display: flex; justify-content: space-between; font-size: 12px; color: var(--dim); margin-bottom: 10px; font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 0.04em; }
.chain-name { color: var(--paper); font-weight: 600; }
.chain-balance { font-size: 19px; font-weight: 600; margin-bottom: 10px; font-family: var(--font-mono); }
.chain-explorer { font-size: 11.5px; color: var(--brand); font-family: var(--font-mono); }

/* ---------- Trade page ---------- */
.trade-page { max-width: 440px; margin: 32px auto; padding: 0 24px; }
.trade-card { background: var(--panel); border: 1px solid var(--hairline); border-radius: var(--radius-md); padding: 22px; }
.trade-tabs { display: flex; gap: 8px; margin-bottom: 18px; }
.trade-tab {
  flex: 1; padding: 10px; border-radius: var(--radius-sm); border: 1px solid var(--hairline);
  background: transparent; color: var(--dim); font-weight: 600; cursor: pointer;
  font-size: 12.5px; text-transform: uppercase; letter-spacing: 0.05em;
}
.trade-tab-active { background: var(--brand-dim); color: var(--brand); border-color: var(--brand); }

.field-label {
  display: block; font-size: 11px; color: var(--dim); margin: 14px 0 6px;
  text-transform: uppercase; letter-spacing: 0.06em; font-family: var(--font-mono);
}
.input, .select {
  width: 100%; background: var(--ink); border: 1px solid var(--hairline);
  color: var(--paper); padding: 12px 14px; border-radius: var(--radius-sm);
  font-size: 14px; outline: none; font-family: var(--font-mono);
}
.input:focus, .select:focus { border-color: var(--brand); }

.quote-box { margin-top: 18px; padding-top: 14px; border-top: 1px solid var(--hairline); }
.quote-box.hidden { display: none; }
.quote-row { display: flex; justify-content: space-between; font-size: 13.5px; margin-bottom: 8px; color: var(--dim); }
.quote-row strong { color: var(--paper); font-family: var(--font-mono); }
.trade-status { margin-top: 14px; font-size: 12.5px; color: var(--dim); min-height: 1.2em; font-family: var(--font-mono); }

/* ---------- Auth pages ---------- */
.auth-page { max-width: 380px; margin: 60px auto; padding: 0 24px; }
.auth-card { background: var(--panel); border: 1px solid var(--hairline); border-radius: var(--radius-md); padding: 26px; }
.auth-card h1 { font-family: var(--font-display); font-size: 18px; margin-top: 0; }
.auth-switch { font-size: 12.5px; color: var(--dim); margin-top: 14px; }
.auth-switch a { color: var(--brand); font-weight: 600; }

/* ---------- Footer ---------- */
.footer {
  max-width: 1100px; margin: 40px auto 20px; padding: 20px 24px 0;
  border-top: 1px solid var(--hairline);
  display: flex; justify-content: space-between; flex-wrap: wrap; gap: 8px;
  color: var(--dim); font-size: 12px; font-family: var(--font-mono);
}
.footer-links { display: flex; gap: 16px; }
.footer-links a:hover { color: var(--paper); }

/* ---------- Chat bubble ---------- */
.chat-bubble { position: fixed; bottom: 20px; right: 20px; z-index: 30; }
.chat-fab {
  width: 50px; height: 50px; border-radius: var(--radius-sm); background: var(--brand);
  border: none; font-size: 19px; cursor: pointer; box-shadow: 0 4px 14px rgba(0,0,0,.4);
}
.chat-popover {
  display: none; position: absolute; bottom: 62px; right: 0; width: 220px;
  background: var(--panel); border: 1px solid var(--hairline); border-radius: var(--radius-md); padding: 14px;
}
.chat-popover.open { display: block; }
.chat-msg { font-size: 13px; margin-bottom: 10px; }
.chat-option {
  display: block; width: 100%; text-align: left; background: transparent;
  border: 1px solid var(--brand); color: var(--brand); border-radius: var(--radius-sm);
  padding: 8px 12px; font-size: 12.5px; margin-bottom: 6px; cursor: pointer;
  font-family: var(--font-mono);
}
.chat-option:hover { background: var(--brand-dim); }

/* ---------- Token detail modal (Bootstrap modal, custom-themed) ---------- */
.token-modal-content {
  background: var(--panel);
  border: 1px solid var(--hairline);
  border-radius: var(--radius-md);
  color: var(--paper);
}
.token-modal-icon { width: 40px; height: 40px; border-radius: var(--radius-sm); object-fit: cover; }
.token-modal-name { font-size: 12.5px; color: var(--dim); }
#tm-symbol { font-family: var(--font-mono); font-weight: 700; }

.tm-stat-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 12px;
  margin-bottom: 16px;
}
.tm-stat {
  background: var(--ink);
  border: 1px solid var(--hairline);
  border-radius: var(--radius-sm);
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.tm-stat span {
  font-size: 10.5px; color: var(--dim); text-transform: uppercase;
  letter-spacing: 0.06em; font-family: var(--font-mono);
}
.tm-stat strong { font-family: var(--font-mono); font-size: 14px; }

.tm-address {
  display: flex; align-items: center; gap: 8px; font-size: 11.5px;
  color: var(--dim); font-family: var(--font-mono);
}
.tm-address code {
  background: var(--ink); border: 1px solid var(--hairline); border-radius: var(--radius-sm);
  padding: 4px 8px; color: var(--paper); overflow-wrap: anywhere; flex: 1;
}

@media (max-width: 640px) {
  .searchbar { display: none; }
  .topnav a:not(.btn-outline):not(.btn-solid) { display: none; }
  .ticker-track { font-size: 11.5px; }
  .tm-stat-grid { grid-template-columns: 1fr; }
}
MEMELAB_EOF

echo ""
echo "Verifying file sizes (none should be 0 bytes):"
for f in app/dex_api.py app/static/js/app.js app/templates/index.html app/static/css/style.css; do
  size=$(wc -c < "$f" 2>/dev/null || echo "MISSING")
  echo "  $f: $size bytes"
  if [ "$size" = "0" ] || [ "$size" = "MISSING" ]; then
    echo "  !!! PROBLEM: $f is empty or missing !!!"
  fi
done
echo ""
echo "Done."
#!/usr/bin/env bash
set -e
echo "Applying dynamic chains + error hardening..."

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
</section>

{% endblock %}

{% block scripts %}
<script>
  MemeDex.initHomepage();
</script>
{% endblock %}
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

  function renderRows(tokens) {
    const tbody = document.getElementById("coin-rows");
    if (!tbody) return;

    if (!tokens.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="empty-row">No tokens found.</td></tr>`;
      return;
    }

    const rows = tokens.map((t) => {
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
    });

    tbody.innerHTML = rows.join("");

    tbody.querySelectorAll("tr[data-pair]").forEach((row) => {
      row.addEventListener("click", () => {
        const chain = row.getAttribute("data-chain");
        const pair = row.getAttribute("data-pair");
        if (chain && pair) showTokenModal(chain, pair);
      });
    });
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
    const copyBtn = document.getElementById("copy-address");
    const confirmEl = document.getElementById("copy-confirm");

    if (copyBtn) {
      copyBtn.addEventListener("click", async () => {
        const address = copyBtn.getAttribute("data-address");
        try {
          await navigator.clipboard.writeText(address);
        } catch {
          // Fallback for browsers without Clipboard API permission.
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

    fetch("/api/wallet/balance")
      .then((r) => r.json())
      .then((data) => {
        if (!data.balances) return;
        Object.entries(data.balances).forEach(([chainKey, info]) => {
          const el = document.querySelector(`[data-balance-for="${chainKey}"]`);
          if (el) {
            const bal = info.native_balance;
            el.textContent = bal !== null && bal !== undefined
              ? `${Number(bal).toFixed(4)} ${info.native_symbol}`
              : `0 ${info.native_symbol}`;
          }
        });
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


def get_trending(chain_id: str = None, limit: int = 80):
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

    # Primary source: a small, diversified set of search terms — kept short
    # deliberately so each refresh is a small burst rather than the 24-request
    # burst that was triggering DexScreener's rate limiter. A brief pause
    # between calls further avoids bursting.
    search_terms = ("pepe", "doge", "wif", "bonk", "shiba", "floki")
    for i, term in enumerate(search_terms):
        if i > 0:
            time.sleep(0.3)
        results.extend(search_tokens(term, limit=20))

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

cat > 'app/routes/api.py' << 'MEMELAB_EOF'
from flask import Blueprint, current_app, jsonify, request
from flask_login import current_user, login_required

from app import dex_api
from app.chain_utils import get_native_balance, get_token_balance
from app.extensions import db
from app.models import Transaction
from app.swap_executor import SwapExecutionError, execute_quote

api_bp = Blueprint("api", __name__)

NATIVE_PLACEHOLDER = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"  # 0x convention for native asset


@api_bp.route("/tokens")
def tokens():
    query = request.args.get("q")
    chain = request.args.get("chain")  # e.g. 'ethereum', 'base', ...
    chain_id = None
    if chain and chain in current_app.config["CHAINS"]:
        chain_id = current_app.config["CHAINS"][chain]["dexscreener_id"]

    if query:
        results = dex_api.search_tokens(query)
        if chain_id:
            results = [r for r in results if r["chain_id"] == chain_id]
    else:
        results = dex_api.get_trending(chain_id=chain_id)

    return jsonify({"tokens": results})


@api_bp.route("/pair/<chain_id>/<pair_address>")
def pair_detail(chain_id, pair_address):
    try:
        pair = dex_api.get_pair(chain_id, pair_address)
    except Exception as e:  # noqa: BLE001 — a detail-view failure should
        # never surface as a raw 500; log it and tell the frontend cleanly.
        current_app.logger.error("pair_detail(%r, %r) crashed: %s", chain_id, pair_address, e)
        return jsonify({"error": "Token temporarily unavailable"}), 502
    if pair is None:
        return jsonify({"error": "Token not found"}), 404
    return jsonify(pair)


@api_bp.route("/wallet/balance")
@login_required
def wallet_balance():
    wallet = current_user.wallet
    if wallet is None:
        return jsonify({"error": "no wallet"}), 404

    balances = {}
    for key, chain in current_app.config["CHAINS"].items():
        balances[key] = {
            "native_symbol": chain["symbol"],
            "native_balance": get_native_balance(chain["rpc"], wallet.address),
        }

    token_address = request.args.get("token")
    chain_key = request.args.get("chain")
    if token_address and chain_key and chain_key in current_app.config["CHAINS"]:
        rpc = current_app.config["CHAINS"][chain_key]["rpc"]
        balances[chain_key]["token_balance"] = get_token_balance(rpc, token_address, wallet.address)

    return jsonify({"address": wallet.address, "balances": balances})


@api_bp.route("/swap/quote", methods=["POST"])
@login_required
def swap_quote():
    data = request.get_json(force=True)
    chain_key = data.get("chain")
    sell_token = data.get("sell_token")
    buy_token = data.get("buy_token")
    sell_amount = data.get("sell_amount")  # smallest unit, as string

    if chain_key not in current_app.config["CHAINS"]:
        return jsonify({"error": "unsupported chain"}), 400

    chain = current_app.config["CHAINS"][chain_key]
    wallet = current_user.wallet

    try:
        quote = dex_api.get_swap_quote(
            api_key=current_app.config["ZEROX_API_KEY"],
            chain_id=chain["zerox_chain"],
            sell_token=sell_token,
            buy_token=buy_token,
            sell_amount=sell_amount,
            taker_address=wallet.address,
        )
    except dex_api.ZeroXError as e:
        return jsonify({"error": str(e)}), 502

    return jsonify(quote)


@api_bp.route("/swap/execute", methods=["POST"])
@login_required
def swap_execute():
    data = request.get_json(force=True)
    chain_key = data.get("chain")
    quote = data.get("quote")
    kind = data.get("kind", "buy")

    if chain_key not in current_app.config["CHAINS"]:
        return jsonify({"error": "unsupported chain"}), 400

    chain = current_app.config["CHAINS"][chain_key]
    wallet = current_user.wallet
    if wallet is None:
        return jsonify({"error": "no wallet"}), 404

    txn = Transaction(
        user_id=current_user.id,
        chain=chain_key,
        kind=kind,
        sell_token=quote.get("sellToken", ""),
        buy_token=quote.get("buyToken", ""),
        sell_amount=str(quote.get("sellAmount", "0")),
        buy_amount=str(quote.get("buyAmount", "")) if quote.get("buyAmount") else None,
        status="pending",
    )
    db.session.add(txn)
    db.session.commit()

    try:
        tx_hash = execute_quote(current_app, chain["rpc"], wallet, quote)
    except SwapExecutionError as e:
        txn.status = "failed"
        db.session.commit()
        return jsonify({"error": str(e)}), 502

    txn.tx_hash = tx_hash
    txn.status = "submitted"
    db.session.commit()

    return jsonify({"tx_hash": tx_hash, "explorer": f"{chain['explorer']}/tx/{tx_hash}"})
MEMELAB_EOF

echo ""
echo "Verifying file sizes (none should be 0 bytes):"
for f in app/templates/index.html app/static/js/app.js app/dex_api.py app/routes/api.py; do
  size=$(wc -c < "$f" 2>/dev/null || echo "MISSING")
  echo "  $f: $size bytes"
  if [ "$size" = "0" ] || [ "$size" = "MISSING" ]; then
    echo "  !!! PROBLEM: $f is empty or missing !!!"
  fi
done
echo ""
echo "Done."
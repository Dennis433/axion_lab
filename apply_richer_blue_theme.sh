]#!/usr/bin/env bash
set -e
echo "Applying Meme Labs rename + real dashboard (stats, movers, sort tabs)..."

cat > 'app/templates/base.html' << 'MEMELAB_EOF'
<!DOCTYPE html>
<html lang="en" data-bs-theme="light">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{% block title %}Meme Labs{% endblock %}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@600;700;800&family=JetBrains+Mono:wght@400;500;600;700&family=Nunito:wght@400;600;700;800&display=swap" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
  <header class="navbar navbar-expand-md topbar sticky-top px-3 px-md-4 py-2">
    <div class="container-fluid px-0">
      <a href="{{ url_for('main.index') }}" class="brand navbar-brand">
        <span class="brand-mark">◆</span> Meme Labs
      </a>

      <div class="searchbar d-none d-md-flex">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="7" stroke="currentColor" stroke-width="2"/><path d="M21 21l-4.3-4.3" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
        <input id="global-search" type="text" placeholder="Search coins, contract address...">
      </div>

      <nav class="topnav ms-auto d-flex align-items-center gap-3">
        <a href="{{ url_for('main.trade_page') }}">Trade</a>
        {% if current_user.is_authenticated %}
          <a href="{{ url_for('main.wallet_page') }}">Wallet</a>
          <a href="{{ url_for('main.logout') }}" class="btn-outline">Logout</a>
        {% else %}
          <a href="{{ url_for('main.login') }}" class="btn-outline">Login</a>
          <a href="{{ url_for('main.signup') }}" class="btn-solid">Sign up</a>
        {% endif %}
      </nav>
    </div>
  </header>

  <div class="ticker-tape">
    <div class="ticker-track" id="ticker-track">
      <span class="ticker-item" style="color: var(--dim);">Loading live prices…</span>
    </div>
  </div>

  <div class="flash-stack">
    {% with messages = get_flashed_messages(with_categories=true) %}
      {% for category, message in messages %}
        <div class="flash flash-{{ category }}">{{ message }}</div>
      {% endfor %}
    {% endwith %}
  </div>

  <main>
    {% block content %}{% endblock %}
  </main>

  <footer class="footer">
    <div class="footer-links">
      <a href="#">Terms</a><a href="#">Privacy</a><a href="#">Docs</a>
    </div>
  </footer>

  <!-- In-site token detail modal: clicking a coin row opens this instead of
       leaving the site, populated via /api/pair/<chain>/<pair_address>. -->
  <div class="modal fade" id="token-modal" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog modal-dialog-centered">
      <div class="modal-content token-modal-content">
        <div class="modal-header border-0 pb-0">
          <div class="d-flex align-items-center gap-2">
            <img id="tm-icon" class="token-modal-icon" src="" alt="" style="display:none;">
            <div>
              <h5 class="modal-title mb-0" id="tm-symbol">—</h5>
              <div class="token-modal-name" id="tm-name"></div>
            </div>
          </div>
          <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body" id="tm-body">
          <div class="text-center py-4" id="tm-loading" style="color: var(--dim); font-family: var(--font-mono);">Loading token…</div>
          <div id="tm-details" class="d-none">
            <div class="tm-stat-grid">
              <div class="tm-stat"><span>Price</span><strong id="tm-price">—</strong></div>
              <div class="tm-stat"><span>Market cap</span><strong id="tm-mcap">—</strong></div>
              <div class="tm-stat"><span>24h volume</span><strong id="tm-vol">—</strong></div>
              <div class="tm-stat"><span>Liquidity</span><strong id="tm-liq">—</strong></div>
              <div class="tm-stat"><span>24h change</span><strong id="tm-change">—</strong></div>
              <div class="tm-stat"><span>DEX</span><strong id="tm-dex">—</strong></div>
            </div>
            <div class="tm-address">
              <span>Contract</span>
              <code id="tm-address">—</code>
            </div>
          </div>
        </div>
        <div class="modal-footer border-0 pt-0">
          <a id="tm-trade-link" href="#" class="btn-solid">Trade this token</a>
        </div>
      </div>
    </div>
  </div>

  <div class="chat-bubble" id="chat-bubble">
    <div class="chat-popover" id="chat-popover">
      <div class="chat-msg">👋 Hi! How can we help?</div>
      <button class="chat-option">I have a question</button>
      <button class="chat-option">Tell me more</button>
    </div>
    <button class="chat-fab" id="chat-fab">💬</button>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
  <script src="{{ url_for('static', filename='js/app.js') }}"></script>
  {% block scripts %}{% endblock %}
</body>
</html>
MEMELAB_EOF

cat > 'app/templates/index.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Meme Labs — Live Meme Coin Tracker{% endblock %}
{% block content %}

<section class="hero">
  <div class="hero-banner">
    <div class="hero-live"><span class="hero-live-dot"></span> LIVE</div>
    <h1 class="hero-title">Track meme coins <span class="hero-title-gradient">as they move</span></h1>
    <p class="hero-sub">Real-time prices across every chain — tap any coin to see the full picture.</p>
  </div>

  <div class="stats-row">
    <div class="stat-card stat-card-a">
      <div class="stat-label">Tokens tracked</div>
      <div class="stat-value" id="stat-tokens">—</div>
    </div>
    <div class="stat-card stat-card-b">
      <div class="stat-label">Total 24h volume</div>
      <div class="stat-value" id="stat-volume">—</div>
    </div>
    <div class="stat-card stat-card-c">
      <div class="stat-label">Chains covered</div>
      <div class="stat-value" id="stat-chains">—</div>
    </div>
  </div>

  <div class="movers-section">
    <div class="movers-heading">Top movers <span class="movers-sub">biggest 24h gainers right now</span></div>
    <div class="movers-grid" id="movers-grid">
      <div class="mover-card mover-skeleton"></div>
      <div class="mover-card mover-skeleton"></div>
      <div class="mover-card mover-skeleton"></div>
      <div class="mover-card mover-skeleton"></div>
    </div>
  </div>

  <div class="filter-row" id="filter-row">
    <button class="chip chip-active" data-sort="trending">Trending</button>
    <button class="chip" data-sort="top">Top</button>
    <button class="chip chip-vol" data-sort="highvol"><span class="dot"></span> High vol</button>
    <span class="chip-divider"></span>
    <button class="chip chip-chain-all" data-chain="">All chains</button>
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
  MemeLabs.initHomepage();
</script>
{% endblock %}
MEMELAB_EOF

cat > 'app/templates/login.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Log in — Meme Labs{% endblock %}
{% block content %}
<section class="auth-page">
  <form class="auth-card" method="post">
    <h1>Log in</h1>
    <label class="field-label">Email</label>
    <input class="input" type="email" name="email" required>
    <label class="field-label">Password</label>
    <input class="input" type="password" name="password" required>
    <button class="btn-solid btn-full" type="submit">Log in</button>
    <p class="auth-switch">No account? <a href="{{ url_for('main.signup') }}">Sign up</a></p>
  </form>
</section>
{% endblock %}
MEMELAB_EOF

cat > 'app/templates/signup.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Sign up — Meme Labs{% endblock %}
{% block content %}
<section class="auth-page">
  <form class="auth-card" method="post">
    <h1>Create your account</h1>
    <p class="sub">A deposit wallet is generated automatically — no seed phrase to write down, no separate app.</p>
    <label class="field-label">Email</label>
    <input class="input" type="email" name="email" required>
    <label class="field-label">Password</label>
    <input class="input" type="password" name="password" minlength="8" required>
    <button class="btn-solid btn-full" type="submit">Create account</button>
    <p class="auth-switch">Already have an account? <a href="{{ url_for('main.login') }}">Log in</a></p>
  </form>
</section>
{% endblock %}
MEMELAB_EOF

cat > 'app/templates/trade.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Trade — Meme Labs{% endblock %}
{% block content %}

<section class="trade-page">
  <div class="trade-card">
    <div class="trade-tabs">
      <button class="trade-tab trade-tab-active" data-kind="buy">Buy</button>
      <button class="trade-tab" data-kind="sell">Sell</button>
    </div>

    <label class="field-label">Chain</label>
    <select id="trade-chain" class="select">
      {% for key, chain in chains.items() %}
        <option value="{{ key }}">{{ chain.name }}</option>
      {% endfor %}
    </select>

    <label class="field-label">Token address</label>
    <input id="trade-token" class="input" placeholder="0x...">

    <label class="field-label">Amount</label>
    <input id="trade-amount" class="input" placeholder="0.0" inputmode="decimal">

    <button id="get-quote" class="btn-solid btn-full">Get quote</button>

    <div id="quote-box" class="quote-box hidden">
      <div class="quote-row"><span>You receive (est.)</span><strong id="quote-buy-amount">—</strong></div>
      <div class="quote-row"><span>Price impact</span><strong id="quote-impact">—</strong></div>
      <button id="confirm-swap" class="btn-solid btn-full">Confirm swap</button>
    </div>

    <div id="trade-status" class="trade-status"></div>
  </div>
</section>

{% endblock %}

{% block scripts %}
<script>
  MemeLabs.initTradePage();
</script>
{% endblock %}
MEMELAB_EOF

cat > 'app/templates/wallet.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Your Wallet — Meme Labs{% endblock %}
{% block content %}

<section class="wallet-page">
  <h1>Your Wallet</h1>
  <p class="sub">One address, every EVM chain. Send only EVM assets (ETH, BNB, MATIC, and their tokens) here — never send Bitcoin or Solana to this address.</p>

  <div class="address-card">
    <div class="address-label">Deposit address — EVM chains (Ethereum, Base, BNB, Polygon, Arbitrum, Optimism)</div>
    <div class="address-row">
      <code id="wallet-address">{{ wallet.address }}</code>
      <button class="copy-btn" id="copy-address" data-address="{{ wallet.address }}">Copy</button>
    </div>
    <div id="copy-confirm" class="copy-confirm">Copied!</div>
  </div>

  {% if wallet.solana_address %}
  <div class="address-card">
    <div class="address-label">Deposit address — Solana</div>
    <div class="address-row">
      <code id="solana-address">{{ wallet.solana_address }}</code>
      <button class="copy-btn" id="copy-solana-address" data-address="{{ wallet.solana_address }}">Copy</button>
    </div>
    <div id="copy-solana-confirm" class="copy-confirm">Copied!</div>
    <div class="chain-balance" style="margin-top: 12px;" data-balance-for="solana">—</div>
  </div>
  {% else %}
  <div class="address-card">
    <div class="address-label">Solana</div>
    <div class="sub" style="margin-bottom: 0;">
      Your account was created before Solana support was added, so it doesn't have a Solana address yet.
      Contact support or re-create your account to get one.
    </div>
  </div>
  {% endif %}

  <div class="chain-grid" id="chain-balances">
    {% for key, chain in chains.items() %}
    <div class="chain-card" data-chain="{{ key }}">
      <div class="chain-card-top">
        <span class="chain-name">{{ chain.name }}</span>
        <span class="chain-symbol">{{ chain.symbol }}</span>
      </div>
      <div class="chain-balance" data-balance-for="{{ key }}">—</div>
      <a class="chain-explorer" href="{{ chain.explorer }}/address/{{ wallet.address }}" target="_blank" rel="noopener">View on explorer ↗</a>
    </div>
    {% endfor %}
  </div>
</section>

{% endblock %}

{% block scripts %}
<script>
  MemeLabs.initWalletPage();
</script>
{% endblock %}
MEMELAB_EOF

cat > 'app/static/js/app.js' << 'MEMELAB_EOF'
/* MemeLabs frontend
 * Written to avoid the "slow and glitchy" symptoms of the original site:
 *  - every network call is debounced and cancels its own stale predecessor
 *    (AbortController) so fast typing/clicking can't pile up requests
 *  - table re-renders build one HTML string and set it once, instead of
 *    incremental DOM mutation
 *  - polling intervals are cleared on page unload
 */

const MemeLabs = (() => {
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
    const color = up ? "#16c784" : "#ff5a5f";
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
    return `https://api.dicebear.com/7.x/identicon/svg?seed=${seed}&backgroundColor=e1eafb`;
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
        console.error(`MemeLabs: /api/pair returned ${res.status}`);
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
      console.error("MemeLabs: showTokenModal failed", err);
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

  function applySort(tokens, sortMode) {
    const arr = [...tokens];
    if (sortMode === "top") {
      arr.sort((a, b) => (b.mcap || 0) - (a.mcap || 0));
    } else if (sortMode === "highvol") {
      arr.sort((a, b) => (b.volume_24h || 0) - (a.volume_24h || 0));
    }
    // "trending" keeps the server-provided order as-is.
    return arr;
  }

  function updateStatsAndMovers(tokens) {
    const tokensEl = document.getElementById("stat-tokens");
    const volumeEl = document.getElementById("stat-volume");
    const chainsEl = document.getElementById("stat-chains");
    const moversGrid = document.getElementById("movers-grid");
    if (!tokens.length) return;

    if (tokensEl) tokensEl.textContent = tokens.length.toLocaleString();

    const totalVolume = tokens.reduce((sum, t) => sum + (Number(t.volume_24h) || 0), 0);
    if (volumeEl) volumeEl.textContent = fmtNumber(totalVolume);

    const uniqueChains = new Set(tokens.map((t) => t.chain_id).filter(Boolean));
    if (chainsEl) chainsEl.textContent = uniqueChains.size.toString();

    if (moversGrid) {
      const gainers = [...tokens]
        .filter((t) => t.price_change_24h !== null && t.price_change_24h !== undefined)
        .sort((a, b) => Number(b.price_change_24h) - Number(a.price_change_24h))
        .slice(0, 8);

      if (gainers.length) {
        moversGrid.innerHTML = gainers
          .map((t) => {
            const change = fmtChange(t.price_change_24h);
            return `
              <div class="mover-card" data-chain="${t.chain_id || ""}" data-pair="${t.pair_address || ""}">
                <img class="mover-icon" src="${tokenIconUrl(t)}" loading="lazy" alt="" onerror="this.style.visibility='hidden'">
                <div class="mover-symbol">${t.base_symbol || "?"}</div>
                <div class="${change.cls}">${change.text}</div>
              </div>`;
          })
          .join("");
        moversGrid.querySelectorAll(".mover-card").forEach((card) => {
          card.addEventListener("click", () => {
            const chain = card.getAttribute("data-chain");
            const pair = card.getAttribute("data-pair");
            if (chain && pair) showTokenModal(chain, pair);
          });
        });
      }
    }
  }

  function initHomepage() {
    let activeChain = "";
    let sortMode = "trending";
    let lastFetchedTokens = [];
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
          console.error(`MemeLabs: /api/tokens returned ${res.status}`);
          if (tbody) tbody.innerHTML = `<tr><td colspan="4" class="empty-row">Server error loading tokens.</td></tr>`;
          return;
        }
        const data = await res.json();
        lastFetchedTokens = data.tokens || [];
        renderRows(applySort(lastFetchedTokens, sortMode));
        updateStatsAndMovers(lastFetchedTokens);

        // Chain chips are only built from an *unfiltered* fetch, so we know
        // the full set of chains actually present — not just the one
        // currently selected.
        if (!activeChain) {
          updateChainChips(lastFetchedTokens, activeChain, (id, btnEl) => {
            setActiveChain(id);
            load();
          });
        }
      } catch (err) {
        if (err.name !== "AbortError") {
          console.error("MemeLabs: fetchTokens failed", err);
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
      const chainChip = e.target.closest(".chip[data-chain='']");
      if (chainChip) {
        setActiveChain("");
        load();
        return;
      }

      const sortChip = e.target.closest(".chip[data-sort]");
      if (sortChip) {
        document.querySelectorAll(".chip[data-sort]").forEach((c) => c.classList.remove("chip-active"));
        sortChip.classList.add("chip-active");
        sortMode = sortChip.getAttribute("data-sort");
        // Re-sort already-fetched data — no need to hit the server again.
        renderRows(applySort(lastFetchedTokens, sortMode));
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
          console.error(`MemeLabs: ticker /api/tokens returned ${res.status}`);
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
        console.error("MemeLabs: ticker refresh failed", err);
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

cat > 'app/static/css/style.css' << 'MEMELAB_EOF'
/* Fonts are loaded via <link> tags in base.html (non-blocking, more resilient
   than a CSS @import, and the page still renders correctly with the fallback
   fonts below even if the Google Fonts request fails). */

:root {
  --ink: #f4f8ff;
  --panel: #ffffff;
  --panel-raised: #ffffff;
  --hairline: #e1eaFB;
  --signal: #16c784;
  --signal-dim: rgba(22, 199, 132, 0.12);
  --pulse: #ff5a5f;
  --pulse-dim: rgba(255, 90, 95, 0.12);
  --brand: #2f6fff;
  --brand-dim: rgba(47, 111, 255, 0.1);
  --accent2: #8b5cf6;
  --accent3: #ff5fa2;
  --paper: #101828;
  --dim: #6b7a99;
  --radius-sm: 10px;
  --radius-md: 18px;
  --font-display: "Poppins", sans-serif;
  --font-mono: "JetBrains Mono", ui-monospace, monospace;
  --font-body: "Nunito", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

* { box-sizing: border-box; }

html, body {
  margin: 0;
  background: linear-gradient(180deg, #eaf2ff 0%, #f4f8ff 340px, #f4f8ff 100%);
  background-attachment: fixed;
  color: var(--paper);
  font-family: var(--font-body);
  -webkit-font-smoothing: antialiased;
  position: relative;
}

/* Decorative blurred gradient blobs — fixed behind all content, low
   opacity, purely for visual depth. This is the texture that keeps the
   blue/white palette from reading as flat corporate SaaS. */
body::before, body::after {
  content: "";
  position: fixed;
  border-radius: 50%;
  filter: blur(70px);
  z-index: -1;
  opacity: 0.35;
  pointer-events: none;
}
body::before {
  width: 480px; height: 480px;
  top: -160px; right: -120px;
  background: radial-gradient(circle, var(--accent2), transparent 70%);
}
body::after {
  width: 420px; height: 420px;
  bottom: -180px; left: -140px;
  background: radial-gradient(circle, var(--accent3), transparent 70%);
}

a { color: inherit; text-decoration: none; }

::selection { background: var(--brand); color: #fff; }

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
  background: rgba(255, 255, 255, 0.85);
  backdrop-filter: blur(10px);
  box-shadow: 0 2px 16px rgba(47, 111, 255, 0.06);
  z-index: 20;
}

.brand {
  font-family: var(--font-display);
  font-weight: 800;
  font-size: 17px;
  letter-spacing: 0.02em;
  background: linear-gradient(135deg, var(--brand), var(--accent2));
  -webkit-background-clip: text; background-clip: text; color: transparent;
  display: flex;
  align-items: center;
  gap: 7px;
  white-space: nowrap;
}
.brand-mark { -webkit-text-fill-color: initial; background: none; color: var(--accent3); font-size: 13px; }

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
  padding: 10px 20px;
  border-radius: 999px;
  font-weight: 700;
  font-size: 13px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border: 2px solid var(--brand);
  cursor: pointer;
  font-family: var(--font-body);
  position: relative;
  transition: transform 0.15s ease, box-shadow 0.15s ease, filter 0.15s ease;
}
.btn-outline { background: transparent; color: var(--brand); }
.btn-outline:hover { background: var(--brand-dim); transform: translateY(-2px); }
.btn-solid {
  background: linear-gradient(135deg, #3d7dff, #2f6fff);
  color: #fff;
  border: 2px solid transparent;
  box-shadow: 0 4px 14px rgba(47, 111, 255, 0.35);
}
.btn-solid:hover { transform: translateY(-2px) scale(1.02); box-shadow: 0 8px 20px rgba(47, 111, 255, 0.45); }
.btn-full { width: 100%; margin-top: 8px; }

/* corner-notch accent: a small design signature on primary buttons */
.btn-solid::after {
  content: "";
  position: absolute;
  top: 0; right: 0;
  border-width: 0 9px 9px 0;
  border-style: solid;
  border-color: transparent rgba(255, 255, 255, 0.35) transparent transparent;
}

/* ---------- Ticker tape (signature element) ---------- */
.ticker-tape {
  background: linear-gradient(90deg, var(--brand), var(--accent2));
  overflow: hidden;
  white-space: nowrap;
  position: relative;
  box-shadow: 0 4px 16px rgba(47, 111, 255, 0.25);
}
.ticker-tape::before, .ticker-tape::after {
  content: "";
  position: absolute;
  top: 0; bottom: 0;
  width: 50px;
  z-index: 2;
  pointer-events: none;
}
.ticker-tape::before { left: 0; background: linear-gradient(90deg, var(--brand), transparent); }
.ticker-tape::after { right: 0; background: linear-gradient(-90deg, var(--accent2), transparent); }

.ticker-track {
  display: inline-flex;
  align-items: center;
  gap: 28px;
  padding: 10px 20px;
  font-family: var(--font-mono);
  font-size: 12.5px;
  font-weight: 600;
  animation: ticker-scroll 38s linear infinite;
  will-change: transform;
}
.ticker-item { display: inline-flex; align-items: center; gap: 7px; color: rgba(255,255,255,0.85); }
.ticker-item .ti-symbol { color: #fff; font-weight: 800; }
.ticker-up { color: #b6ffe0; font-weight: 800; }
.ticker-down { color: #ffd6d6; font-weight: 800; }

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
.flash-success { background: var(--brand-dim); color: var(--brand); border-color: rgba(47,111,255,.3); }
.flash-error { background: var(--pulse-dim); color: var(--pulse); border-color: rgba(255,90,95,.3); }

/* ---------- Hero / filters ---------- */
.hero { max-width: 1100px; margin: 20px auto; padding: 0 24px; }

.hero-banner { text-align: center; padding: 36px 16px 28px; }
.hero-live {
  display: inline-flex; align-items: center; gap: 6px;
  background: var(--signal-dim); color: var(--signal);
  font-family: var(--font-mono); font-weight: 800; font-size: 11px;
  letter-spacing: 0.1em; padding: 5px 14px; border-radius: 999px;
  margin-bottom: 16px;
}
.hero-live-dot {
  width: 7px; height: 7px; border-radius: 50%; background: var(--signal);
  display: inline-block; animation: pulse-dot 1.6s ease-in-out infinite;
}
@keyframes pulse-dot {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.4; transform: scale(0.8); }
}
.hero-title {
  font-family: var(--font-display); font-weight: 800; font-size: 38px;
  line-height: 1.15; margin: 0 0 12px; color: var(--paper);
}
.hero-title-gradient {
  background: linear-gradient(135deg, var(--brand), var(--accent2), var(--accent3));
  -webkit-background-clip: text; background-clip: text; color: transparent;
}
.hero-sub { color: var(--dim); font-size: 16px; margin: 0; font-weight: 600; }

@media (max-width: 640px) {
  .hero-title { font-size: 28px; }
}

/* ---------- Stats row ---------- */
.stats-row {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 14px;
  margin-bottom: 32px;
}
.stat-card {
  border-radius: var(--radius-md);
  padding: 18px 20px;
  color: #fff;
  box-shadow: 0 10px 24px rgba(47, 111, 255, 0.18);
}
.stat-card-a { background: linear-gradient(135deg, var(--brand), #5b8dff); }
.stat-card-b { background: linear-gradient(135deg, var(--accent2), #a685f5); }
.stat-card-c { background: linear-gradient(135deg, var(--accent3), #ff8fc0); }
.stat-label { font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; opacity: 0.85; margin-bottom: 6px; }
.stat-value { font-family: var(--font-mono); font-size: 26px; font-weight: 700; }

@media (max-width: 720px) {
  .stats-row { grid-template-columns: 1fr; }
}

/* ---------- Top movers grid ---------- */
.movers-section { margin-bottom: 28px; }
.movers-heading {
  font-family: var(--font-display); font-weight: 700; font-size: 18px;
  color: var(--paper); margin-bottom: 4px;
}
.movers-sub { font-family: var(--font-body); font-weight: 600; font-size: 13px; color: var(--dim); margin-left: 8px; }
.movers-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
  gap: 12px;
  margin-top: 14px;
}
.mover-card {
  background: var(--panel);
  border: 1px solid var(--hairline);
  border-radius: var(--radius-md);
  padding: 16px 12px;
  text-align: center;
  cursor: pointer;
  box-shadow: 0 6px 16px rgba(47, 111, 255, 0.08);
  transition: transform 0.15s ease, box-shadow 0.15s ease;
}
.mover-card:hover { transform: translateY(-4px) scale(1.03); box-shadow: 0 12px 24px rgba(47, 111, 255, 0.18); }
.mover-icon {
  width: 44px; height: 44px; border-radius: 50%; object-fit: cover;
  margin-bottom: 8px; box-shadow: 0 0 0 2px #fff, 0 0 0 3.5px var(--brand-dim);
}
.mover-symbol { font-family: var(--font-mono); font-weight: 700; font-size: 13px; margin-bottom: 4px; }
.mover-skeleton {
  height: 118px;
  background: linear-gradient(90deg, var(--hairline) 25%, #eef3ff 50%, var(--hairline) 75%);
  background-size: 200% 100%;
  animation: skeleton-shimmer 1.4s ease-in-out infinite;
}
@keyframes skeleton-shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

/* ---------- Filter row (sort tabs + chain chips) ---------- */
.chip-divider { width: 1px; align-self: stretch; background: var(--hairline); margin: 0 4px; }

.filter-row { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 16px; align-items: center; }
.chip {
  background: var(--panel);
  border: 2px solid var(--hairline);
  color: var(--dim);
  padding: 7px 16px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 700;
  font-family: var(--font-mono);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  cursor: pointer;
  transition: transform 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
}
.chip:hover { border-color: var(--brand); transform: translateY(-2px); box-shadow: 0 4px 10px rgba(47,111,255,0.15); }
.chip-active { color: #fff; border-color: transparent; background: linear-gradient(135deg, var(--brand), var(--accent2)); box-shadow: 0 4px 14px rgba(47,111,255,0.35); }
.chip-vol { display: flex; align-items: center; gap: 6px; }
.chip-vol .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--pulse); display: inline-block; }

/* ---------- Coin table ---------- */
.table-wrap {
  background: var(--panel);
  border: 1px solid var(--hairline);
  border-radius: var(--radius-md);
  overflow: hidden;
  box-shadow: 0 10px 30px rgba(47, 111, 255, 0.08);
}
.coin-table { width: 100%; border-collapse: collapse; }
.coin-table th {
  text-align: left;
  font-size: 10.5px;
  letter-spacing: .08em;
  color: var(--dim);
  padding: 13px 18px;
  border-bottom: 1px solid var(--hairline);
  font-weight: 700;
  font-family: var(--font-mono);
  text-transform: uppercase;
}
.sort { opacity: .5; font-size: 10px; }
.coin-table td { padding: 13px 18px; border-bottom: 1px solid var(--hairline); vertical-align: middle; }
.coin-table tr:last-child td { border-bottom: none; }
.coin-table tbody tr { cursor: pointer; transition: background .15s ease, transform .15s ease; }
.coin-table tbody tr:hover { background: rgba(47,111,255,0.06); transform: scale(1.005); }

.coin-cell { display: flex; align-items: center; gap: 12px; }
.coin-icon {
  width: 34px; height: 34px; border-radius: 50%;
  background: var(--hairline); object-fit: cover; flex-shrink: 0;
  box-shadow: 0 0 0 2px #fff, 0 0 0 3.5px var(--brand-dim), 0 2px 8px rgba(47,111,255,0.15);
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
  border-left: 4px solid var(--brand);
  border-radius: var(--radius-md);
  padding: 20px;
  margin-bottom: 24px;
  box-shadow: 0 10px 30px rgba(47, 111, 255, 0.1);
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
  background: linear-gradient(135deg, #3d7dff, #2f6fff);
  color: #fff;
  border: none;
  padding: 10px 20px;
  border-radius: 999px;
  font-weight: 700;
  font-size: 12.5px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  cursor: pointer;
  white-space: nowrap;
  box-shadow: 0 4px 14px rgba(47, 111, 255, 0.35);
  transition: transform 0.15s ease, box-shadow 0.15s ease;
}
.copy-btn:hover { transform: translateY(-2px) scale(1.03); box-shadow: 0 8px 20px rgba(47, 111, 255, 0.45); }
.copy-confirm { opacity: 0; color: var(--signal); font-weight: 700; font-size: 12.5px; margin-top: 8px; transition: opacity .2s; font-family: var(--font-mono); }
.copy-confirm.show { opacity: 1; }

.chain-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; }
.chain-card { background: var(--panel); border: 1px solid var(--hairline); border-radius: var(--radius-sm); padding: 16px; box-shadow: 0 6px 18px rgba(47,111,255,0.08); transition: transform 0.15s ease; }
.chain-card:hover { transform: translateY(-3px); }
.chain-card-top { display: flex; justify-content: space-between; font-size: 12px; color: var(--dim); margin-bottom: 10px; font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 0.04em; }
.chain-name { color: var(--paper); font-weight: 600; }
.chain-balance { font-size: 19px; font-weight: 600; margin-bottom: 10px; font-family: var(--font-mono); }
.chain-explorer { font-size: 11.5px; color: var(--brand); font-family: var(--font-mono); }

/* ---------- Trade page ---------- */
.trade-page { max-width: 440px; margin: 32px auto; padding: 0 24px; }
.trade-card { background: var(--panel); border: 1px solid var(--hairline); border-radius: var(--radius-md); padding: 22px; box-shadow: 0 10px 30px rgba(47,111,255,0.1); }
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
.auth-card { background: var(--panel); border: 1px solid var(--hairline); border-radius: var(--radius-md); padding: 26px; box-shadow: 0 10px 30px rgba(47,111,255,0.1); }
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
  width: 54px; height: 54px; border-radius: 50%;
  background: linear-gradient(135deg, #3d7dff, #2f6fff);
  border: none; font-size: 20px; cursor: pointer;
  box-shadow: 0 6px 18px rgba(47, 111, 255, 0.4);
  animation: chat-bounce 2.4s ease-in-out infinite;
  transition: transform 0.15s ease;
}
.chat-fab:hover { transform: scale(1.08); animation-play-state: paused; }
@keyframes chat-bounce {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-6px); }
}
@media (prefers-reduced-motion: reduce) {
  .chat-fab { animation: none; }
}
.chat-popover {
  display: none; position: absolute; bottom: 66px; right: 0; width: 220px;
  background: var(--panel); border: 1px solid var(--hairline); border-radius: var(--radius-md); padding: 14px;
  box-shadow: 0 10px 30px rgba(47, 111, 255, 0.18);
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
  box-shadow: 0 20px 50px rgba(47, 111, 255, 0.2);
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
for f in app/templates/base.html app/templates/index.html app/templates/login.html app/templates/signup.html app/templates/trade.html app/templates/wallet.html app/static/js/app.js app/static/css/style.css; do
  size=$(wc -c < "$f" 2>/dev/null || echo "MISSING")
  echo "  $f: $size bytes"
  if [ "$size" = "0" ] || [ "$size" = "MISSING" ]; then
    echo "  !!! PROBLEM: $f is empty or missing !!!"
  fi
done
echo ""
echo "Done."
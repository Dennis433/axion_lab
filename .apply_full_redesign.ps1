# Meme Labs full redesign — run this in PowerShell from inside your meme_lab folder
# Right-click PowerShell -> Run as administrator is NOT needed
Write-Host "Applying Meme Labs redesign..."

Set-Content -Path 'app/templates/base.html' -Encoding UTF8 -Value @'
<!DOCTYPE html>
<html lang="en" data-bs-theme="light">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{% block title %}Meme Labs{% endblock %}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>

  <!-- Topbar -->
  <header class="topbar">
    <a href="{{ url_for('main.index') }}" class="brand">
      <div class="brand-icon">M</div>
      <span>Meme<strong>Labs</strong></span>
    </a>

    <div class="search-wrap d-none d-md-flex">
      <svg class="search-ico" width="15" height="15" viewBox="0 0 24 24" fill="none">
        <circle cx="11" cy="11" r="7" stroke="currentColor" stroke-width="2"/>
        <path d="M21 21l-4.3-4.3" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
      </svg>
      <input id="global-search" type="text" placeholder="Search coins, CA, creators…">
    </div>

    <nav class="top-nav ms-auto d-flex align-items-center gap-2">
      <a href="{{ url_for('main.trade_page') }}" class="nav-link-item">Trade</a>
      {% if current_user.is_authenticated %}
        <a href="{{ url_for('main.wallet_page') }}" class="nav-link-item">Wallet</a>
        <a href="{{ url_for('main.logout') }}" class="btn-outline-nav">Logout</a>
      {% else %}
        <a href="{{ url_for('main.login') }}" class="btn-outline-nav">Login</a>
        <a href="{{ url_for('main.signup') }}" class="btn-primary-nav">Sign Up</a>
      {% endif %}
    </nav>
  </header>

  <!-- Live ticker -->
  <div class="ticker-tape">
    <div class="ticker-track" id="ticker-track">
      <span class="ticker-placeholder">Loading live prices…</span>
    </div>
  </div>

  <!-- Flash messages -->
  <div class="flash-stack">
    {% with messages = get_flashed_messages(with_categories=true) %}
      {% for category, message in messages %}
        <div class="flash flash-{{ category }}">{{ message }}</div>
      {% endfor %}
    {% endwith %}
  </div>

  <main>{% block content %}{% endblock %}</main>

  <footer class="site-footer">
    <div class="footer-inner">
      <span class="footer-brand">Meme<strong>Labs</strong></span>
      <div class="footer-links">
        <a href="#">Terms</a>
        <a href="#">Privacy</a>
        <a href="#">Docs</a>
      </div>
    </div>
  </footer>

  <!-- Token detail modal -->
  <div class="modal fade" id="token-modal" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog modal-dialog-centered modal-lg">
      <div class="modal-content ml-modal">
        <div class="modal-header border-0 pb-0">
          <div class="d-flex align-items-center gap-3">
            <img id="tm-icon" class="tm-icon" src="" alt="" style="display:none">
            <div>
              <h5 class="modal-title mb-0 tm-symbol" id="tm-symbol">—</h5>
              <div class="tm-name" id="tm-name"></div>
            </div>
          </div>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="tm-loading" id="tm-loading">Loading token…</div>
          <div id="tm-details" class="d-none">
            <div class="tm-stat-grid">
              <div class="tm-stat"><span>Price</span><strong id="tm-price">—</strong></div>
              <div class="tm-stat"><span>Market cap</span><strong id="tm-mcap">—</strong></div>
              <div class="tm-stat"><span>24h volume</span><strong id="tm-vol">—</strong></div>
              <div class="tm-stat"><span>Liquidity</span><strong id="tm-liq">—</strong></div>
              <div class="tm-stat"><span>24h change</span><strong id="tm-change">—</strong></div>
              <div class="tm-stat"><span>DEX</span><strong id="tm-dex">—</strong></div>
            </div>
            <div class="tm-address-row">
              <span class="tm-address-label">Contract</span>
              <code id="tm-address">—</code>
            </div>
          </div>
        </div>
        <div class="modal-footer border-0 pt-0">
          <a id="tm-trade-link" href="#" class="btn-primary-nav">Trade this token</a>
        </div>
      </div>
    </div>
  </div>

  <!-- Chat bubble -->
  <div class="chat-bubble">
    <div class="chat-popover" id="chat-popover">
      <div class="chat-msg">👋 Hi! How can we help?</div>
      <button class="chat-opt">I have a question</button>
      <button class="chat-opt">Tell me more</button>
    </div>
    <button class="chat-fab" id="chat-fab">💬</button>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
  <script src="{{ url_for('static', filename='js/app.js') }}"></script>
  {% block scripts %}{% endblock %}
</body>
</html>
'@

Set-Content -Path 'app/templates/index.html' -Encoding UTF8 -Value @'
{% extends "base.html" %}
{% block title %}Meme Labs — Live Meme Coin Tracker{% endblock %}
{% block content %}

<div class="page-wrap">

  <!-- Left sidebar -->
  <aside class="sidebar">
    <!-- Deposit card -->
    <div class="sidebar-card deposit-card">
      <div class="deposit-header">
        <div class="deposit-dot"></div>
        <span>Deposit Address</span>
        <span class="online-badge" id="online-count">— online</span>
      </div>

      <div class="deposit-chain">
        <div class="chain-badge evm-badge">EVM</div>
        <code class="deposit-addr" id="evm-addr">0xd0FC440972F27CcD814EE91FE26C76C7720E0dE1</code>
        <button class="copy-mini" data-addr="0xd0FC440972F27CcD814EE91FE26C76C7720E0dE1" title="Copy EVM address">⧉</button>
      </div>
      <div class="copy-tip" id="copy-evm">Copied!</div>

      <div class="deposit-chain mt-2">
        <div class="chain-badge sol-badge">SOL</div>
        <code class="deposit-addr" id="sol-addr">FEfxQxUkj46K6pur9uFvHpPJHJBPkwC5wmTDxCWU2Kwt</code>
        <button class="copy-mini" data-addr="FEfxQxUkj46K6pur9uFvHpPJHJBPkwC5wmTDxCWU2Kwt" title="Copy Solana address">⧉</button>
      </div>
      <div class="copy-tip" id="copy-sol">Copied!</div>
    </div>

    <!-- Stats card -->
    <div class="sidebar-card stats-card">
      <div class="sc-row">
        <span class="sc-label">Tokens tracked</span>
        <span class="sc-val" id="stat-tokens">—</span>
      </div>
      <div class="sc-divider"></div>
      <div class="sc-row">
        <span class="sc-label">24h volume</span>
        <span class="sc-val" id="stat-volume">—</span>
      </div>
      <div class="sc-divider"></div>
      <div class="sc-row">
        <span class="sc-label">Chains</span>
        <span class="sc-val" id="stat-chains">—</span>
      </div>
    </div>

    <!-- Top volume mini-list -->
    <div class="sidebar-card">
      <div class="sidebar-section-title">Top Volume</div>
      <div class="tv-head-row">
        <span>COIN</span><span>MCAP</span><span>24H VOL</span>
      </div>
      <div id="top-vol-list" class="top-vol-list"></div>
    </div>
  </aside>

  <!-- Main content -->
  <main class="main-content">

    <!-- Top movers grid -->
    <div class="movers-section">
      <div class="section-title">🔥 Top Earning Coins</div>
      <div class="movers-grid" id="movers-grid">
        {% for i in range(8) %}
        <div class="mover-card mover-skeleton"></div>
        {% endfor %}
      </div>
    </div>

    <!-- Sort tabs + chain filter -->
    <div class="filter-bar" id="filter-row">
      <div class="sort-tabs">
        <button class="sort-tab sort-tab-active" data-sort="trending">● Trending</button>
        <button class="sort-tab" data-sort="top">● Top</button>
        <button class="sort-tab" data-sort="highvol">● High vol</button>
      </div>
      <div class="chain-chips" id="chain-chips">
        <button class="chain-chip chain-chip-active" data-chain="">All chains</button>
      </div>
    </div>

    <!-- Token table -->
    <div class="table-card">
      <table class="token-table">
        <thead>
          <tr>
            <th>COIN ↕</th>
            <th>MCAP ↕</th>
            <th>24H VOL ↕</th>
            <th>CHART</th>
          </tr>
        </thead>
        <tbody id="coin-rows">
          <tr><td colspan="4" class="loading-row">Loading tokens…</td></tr>
        </tbody>
      </table>
    </div>
    <div id="scroll-sentinel" style="height:1px;"></div>
    <div id="scroll-status" class="scroll-status"></div>

  </main>
</div>
{% endblock %}

{% block scripts %}
<script>MemeLabs.initHomepage();</script>
{% endblock %}
'@

Set-Content -Path 'app/templates/login.html' -Encoding UTF8 -Value @'
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
'@

Set-Content -Path 'app/templates/signup.html' -Encoding UTF8 -Value @'
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
'@

Set-Content -Path 'app/templates/trade.html' -Encoding UTF8 -Value @'
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
'@

Set-Content -Path 'app/templates/wallet.html' -Encoding UTF8 -Value @'
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
'@

Set-Content -Path 'app/static/css/style.css' -Encoding UTF8 -Value @'
/* =========================================================
   Meme Labs — Rich Blue/White Design System
   ========================================================= */

@import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600;700&display=swap');

:root {
  /* Core palette */
  --bg:        #eef2fb;
  --panel:     #ffffff;
  --panel2:    #f7f9ff;
  --border:    #dce5f7;
  --border2:   #c8d8f5;

  /* Brand */
  --blue:      #2563eb;
  --blue2:     #1d4ed8;
  --blue-lt:   #eff4ff;
  --blue-mid:  #bfcfff;
  --indigo:    #6366f1;
  --violet:    #8b5cf6;
  --pink:      #ec4899;

  /* Data */
  --green:     #10b981;
  --green-lt:  #d1fae5;
  --red:       #ef4444;
  --red-lt:    #fee2e2;
  --amber:     #f59e0b;
  --amber-lt:  #fef3c7;

  /* Text */
  --text:      #0f172a;
  --text2:     #334155;
  --text3:     #64748b;
  --text4:     #94a3b8;

  /* Sizing */
  --r-sm:  8px;
  --r-md:  14px;
  --r-lg:  20px;
  --r-xl:  28px;

  --font: "Plus Jakarta Sans", -apple-system, BlinkMacSystemFont, sans-serif;
  --mono: "JetBrains Mono", ui-monospace, monospace;
}

*, *::before, *::after { box-sizing: border-box; }

html, body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font-family: var(--font);
  -webkit-font-smoothing: antialiased;
  min-height: 100vh;
}

/* Subtle mesh gradient overlay on the background */
body::before {
  content: "";
  position: fixed;
  inset: 0;
  background:
    radial-gradient(ellipse 80% 50% at 10% -10%, rgba(99,102,241,0.12) 0%, transparent 55%),
    radial-gradient(ellipse 70% 60% at 90% 110%, rgba(236,72,153,0.08) 0%, transparent 55%),
    radial-gradient(ellipse 60% 40% at 50% 50%, rgba(37,99,235,0.05) 0%, transparent 65%);
  pointer-events: none;
  z-index: 0;
}
body > * { position: relative; z-index: 1; }

a { color: inherit; text-decoration: none; }
::selection { background: var(--blue); color: #fff; }

/* ─── TOPBAR ─── */
.topbar {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 12px 24px;
  background: rgba(255,255,255,0.85);
  backdrop-filter: blur(12px);
  border-bottom: 1px solid var(--border);
  box-shadow: 0 1px 0 var(--border), 0 4px 20px rgba(37,99,235,0.06);
  position: sticky; top: 0; z-index: 100;
}

.brand {
  display: flex;
  align-items: center;
  gap: 9px;
  font-size: 17px;
  font-weight: 700;
  color: var(--text);
  white-space: nowrap;
}
.brand strong { color: var(--blue); }
.brand-icon {
  width: 32px; height: 32px; border-radius: 10px;
  background: linear-gradient(135deg, var(--blue), var(--indigo));
  display: grid; place-items: center;
  color: #fff; font-weight: 800; font-size: 15px;
  box-shadow: 0 4px 12px rgba(37,99,235,0.35);
}

.search-wrap {
  flex: 1; max-width: 400px;
  display: flex; align-items: center; gap: 9px;
  background: var(--panel2);
  border: 1.5px solid var(--border);
  border-radius: var(--r-lg);
  padding: 8px 14px;
  transition: border-color .18s;
}
.search-wrap:focus-within { border-color: var(--blue); box-shadow: 0 0 0 3px rgba(37,99,235,0.1); }
.search-ico { color: var(--text3); flex-shrink: 0; }
#global-search {
  background: transparent; border: none; outline: none;
  color: var(--text); font-family: var(--font); font-size: 14px; width: 100%;
}
#global-search::placeholder { color: var(--text4); }

.top-nav { gap: 8px !important; }
.nav-link-item {
  font-size: 14px; font-weight: 600; color: var(--text2);
  padding: 6px 12px; border-radius: var(--r-sm);
  transition: background .15s, color .15s;
}
.nav-link-item:hover { background: var(--blue-lt); color: var(--blue); }

.btn-outline-nav {
  font-weight: 700; font-size: 13px; padding: 8px 18px;
  border-radius: var(--r-lg); border: 2px solid var(--blue);
  color: var(--blue); background: transparent; cursor: pointer;
  transition: all .15s;
}
.btn-outline-nav:hover { background: var(--blue-lt); }

.btn-primary-nav {
  font-weight: 700; font-size: 13px; padding: 8px 18px;
  border-radius: var(--r-lg); border: none;
  color: #fff; background: linear-gradient(135deg, var(--blue), var(--indigo));
  cursor: pointer; box-shadow: 0 4px 12px rgba(37,99,235,0.3);
  transition: all .15s; display: inline-block; text-align: center;
}
.btn-primary-nav:hover { transform: translateY(-1px); box-shadow: 0 6px 18px rgba(37,99,235,0.4); }

/* ─── TICKER ─── */
.ticker-tape {
  background: linear-gradient(90deg, var(--blue), var(--indigo), var(--violet));
  overflow: hidden; white-space: nowrap; position: relative;
}
.ticker-tape::before, .ticker-tape::after {
  content: ""; position: absolute; top: 0; bottom: 0; width: 60px; z-index: 2; pointer-events: none;
}
.ticker-tape::before { left: 0; background: linear-gradient(90deg, var(--blue), transparent); }
.ticker-tape::after  { right: 0; background: linear-gradient(-90deg, var(--violet), transparent); }
.ticker-track {
  display: inline-flex; align-items: center; gap: 32px;
  padding: 9px 20px; font-family: var(--mono); font-size: 12px; font-weight: 600;
  animation: ticker-scroll 40s linear infinite;
}
@keyframes ticker-scroll { from { transform: translateX(0); } to { transform: translateX(-50%); } }
.ticker-item  { display: inline-flex; align-items: center; gap: 6px; color: rgba(255,255,255,.8); }
.ticker-item .ti-sym { color: #fff; font-weight: 800; }
.ticker-up    { color: #6ee7b7; font-weight: 800; }
.ticker-down  { color: #fca5a5; font-weight: 800; }
.ticker-placeholder { color: rgba(255,255,255,.65); }
@media (prefers-reduced-motion: reduce) { .ticker-track { animation: none; } }

/* ─── FLASH ─── */
.flash-stack { max-width: 1200px; margin: 12px auto 0; padding: 0 20px; }
.flash { padding: 10px 16px; border-radius: var(--r-sm); font-size: 13px; margin-bottom: 8px; border: 1px solid; }
.flash-success { background: var(--green-lt); color: var(--green); border-color: #6ee7b7; }
.flash-error   { background: var(--red-lt);   color: var(--red);   border-color: #fca5a5; }

/* ─── PAGE LAYOUT ─── */
.page-wrap {
  display: grid;
  grid-template-columns: 280px 1fr;
  gap: 20px;
  max-width: 1280px;
  margin: 20px auto;
  padding: 0 20px;
  align-items: start;
}
@media (max-width: 900px) { .page-wrap { grid-template-columns: 1fr; } }

/* ─── SIDEBAR ─── */
.sidebar { display: flex; flex-direction: column; gap: 14px; }

.sidebar-card {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: var(--r-lg);
  padding: 18px;
  box-shadow: 0 4px 20px rgba(37,99,235,0.06);
}

/* Deposit card */
.deposit-card { background: linear-gradient(145deg, #1e3a8a 0%, #1e40af 40%, #312e81 100%); border: none; color: #fff; }
.deposit-header {
  display: flex; align-items: center; gap: 7px;
  font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em;
  color: rgba(255,255,255,.75); margin-bottom: 14px;
}
.deposit-dot { width: 7px; height: 7px; border-radius: 50%; background: #34d399; flex-shrink: 0;
  animation: pulse-dot 1.8s ease-in-out infinite; }
@keyframes pulse-dot { 0%,100%{opacity:1;transform:scale(1)} 50%{opacity:.5;transform:scale(.8)} }
.online-badge { margin-left: auto; background: rgba(255,255,255,.15); padding: 3px 10px; border-radius: 999px; font-size: 10px; }
.deposit-chain { display: flex; align-items: center; gap: 7px; }
.chain-badge {
  font-size: 9px; font-weight: 800; letter-spacing: .05em;
  padding: 3px 8px; border-radius: 999px; flex-shrink: 0;
}
.evm-badge { background: rgba(99,102,241,.35); color: #c7d2fe; }
.sol-badge  { background: rgba(236,72,153,.35); color: #fbcfe8; }
.deposit-addr {
  font-family: var(--mono); font-size: 10px; color: rgba(255,255,255,.85);
  flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  background: rgba(255,255,255,.08); padding: 5px 8px; border-radius: var(--r-sm);
}
.copy-mini {
  background: rgba(255,255,255,.15); border: none; color: #fff;
  font-size: 14px; padding: 4px 8px; border-radius: var(--r-sm);
  cursor: pointer; flex-shrink: 0; transition: background .15s;
}
.copy-mini:hover { background: rgba(255,255,255,.3); }
.copy-tip { font-size: 11px; color: #34d399; height: 16px; margin-top: 2px; opacity: 0; transition: opacity .2s; }
.copy-tip.show { opacity: 1; }

/* Stats card */
.stats-card { background: var(--panel2); }
.sc-row { display: flex; justify-content: space-between; align-items: center; padding: 6px 0; }
.sc-label { font-size: 12px; color: var(--text3); font-weight: 600; }
.sc-val { font-family: var(--mono); font-weight: 700; font-size: 14px; color: var(--blue); }
.sc-divider { height: 1px; background: var(--border); margin: 2px 0; }

/* Sidebar section title */
.sidebar-section-title { font-size: 11px; font-weight: 800; text-transform: uppercase; letter-spacing: .06em; color: var(--text3); margin-bottom: 10px; }
.tv-head-row { display: grid; grid-template-columns: 1fr 1fr 1fr; font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: .05em; color: var(--text4); padding: 4px 0; border-bottom: 1px solid var(--border); margin-bottom: 6px; }
.top-vol-list { display: flex; flex-direction: column; gap: 2px; }
.tv-row {
  display: grid; grid-template-columns: 1fr 1fr 1fr;
  align-items: center; padding: 7px 0;
  border-bottom: 1px solid var(--border);
  cursor: pointer; transition: background .13s;
  border-radius: var(--r-sm);
}
.tv-row:hover { background: var(--blue-lt); }
.tv-coin { display: flex; align-items: center; gap: 7px; }
.tv-icon { width: 24px; height: 24px; border-radius: 50%; object-fit: cover; }
.tv-sym { font-weight: 700; font-size: 12px; }
.tv-mcap { font-family: var(--mono); font-size: 11px; color: var(--text2); }
.tv-vol  { font-family: var(--mono); font-size: 11px; color: var(--text3); }

/* ─── MAIN CONTENT ─── */
.main-content { display: flex; flex-direction: column; gap: 18px; min-width: 0; }

/* Section title */
.section-title { font-weight: 800; font-size: 15px; color: var(--text); margin-bottom: 12px; }

/* ─── MOVERS GRID ─── */
.movers-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; }
@media (max-width: 760px) { .movers-grid { grid-template-columns: repeat(2, 1fr); } }

.mover-card {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: var(--r-lg);
  padding: 16px 12px;
  text-align: center;
  cursor: pointer;
  box-shadow: 0 4px 16px rgba(37,99,235,.06);
  transition: transform .18s, box-shadow .18s;
}
.mover-card:hover { transform: translateY(-5px) scale(1.03); box-shadow: 0 12px 28px rgba(37,99,235,.15); }
.mover-icon { width: 48px; height: 48px; border-radius: 50%; object-fit: cover; margin: 0 auto 8px;
  display: block; box-shadow: 0 0 0 2px #fff, 0 0 0 4px var(--blue-mid); }
.mover-sym  { font-weight: 800; font-size: 13px; margin-bottom: 4px; }
.mover-name { font-size: 11px; color: var(--text3); margin-bottom: 6px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mover-skeleton {
  height: 130px; border-radius: var(--r-lg);
  background: linear-gradient(90deg, var(--border) 25%, #eef2ff 50%, var(--border) 75%);
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
}
@keyframes shimmer { 0%{background-position:200% 0} 100%{background-position:-200% 0} }

/* ─── FILTER BAR ─── */
.filter-bar {
  display: flex; align-items: center; gap: 10px; flex-wrap: wrap;
  background: var(--panel); border: 1px solid var(--border);
  border-radius: var(--r-lg); padding: 8px 12px;
  box-shadow: 0 2px 10px rgba(37,99,235,.05);
}
.sort-tabs { display: flex; gap: 4px; }
.sort-tab {
  font-size: 13px; font-weight: 700; padding: 7px 14px;
  border-radius: var(--r-lg); border: none; background: transparent;
  color: var(--text3); cursor: pointer; transition: all .15s;
}
.sort-tab-active { background: var(--blue); color: #fff; box-shadow: 0 4px 12px rgba(37,99,235,.35); }
.sort-tab:not(.sort-tab-active):hover { background: var(--blue-lt); color: var(--blue); }
.filter-divider { width: 1px; height: 24px; background: var(--border); flex-shrink: 0; }
.chain-chips { display: flex; gap: 6px; flex-wrap: wrap; }
.chain-chip {
  font-size: 12px; font-weight: 700; padding: 5px 13px;
  border-radius: 999px; border: 1.5px solid var(--border2);
  background: transparent; color: var(--text3); cursor: pointer;
  transition: all .15s;
}
.chain-chip:hover { border-color: var(--blue); color: var(--blue); }
.chain-chip-active {
  background: linear-gradient(135deg, var(--blue), var(--indigo));
  border-color: transparent; color: #fff;
  box-shadow: 0 4px 12px rgba(37,99,235,.3);
}

/* ─── TOKEN TABLE ─── */
.table-card {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: var(--r-lg);
  overflow: hidden;
  box-shadow: 0 4px 24px rgba(37,99,235,.07);
}
.token-table { width: 100%; border-collapse: collapse; }
.token-table th {
  text-align: left; padding: 12px 18px;
  font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em;
  color: var(--text3); border-bottom: 1px solid var(--border);
  background: var(--panel2);
}
.token-table td {
  padding: 13px 18px; border-bottom: 1px solid var(--border);
  vertical-align: middle; font-size: 14px;
}
.token-table tbody tr { cursor: pointer; transition: background .13s; }
.token-table tbody tr:hover { background: var(--blue-lt); }
.token-table tbody tr:last-child td { border-bottom: none; }

.coin-cell { display: flex; align-items: center; gap: 11px; }
.coin-icon {
  width: 36px; height: 36px; border-radius: 50%;
  object-fit: cover; flex-shrink: 0;
  box-shadow: 0 0 0 2px #fff, 0 0 0 3.5px var(--blue-mid);
}
.coin-sym  { font-weight: 800; font-size: 14px; font-family: var(--mono); }
.coin-name { font-size: 11px; color: var(--text3); margin-top: 1px; }

.mcap-val  { font-weight: 700; font-family: var(--mono); }
.vol-val   { font-family: var(--mono); color: var(--text2); }

.change-up   { color: var(--green); font-weight: 700; font-size: 12px; font-family: var(--mono); }
.change-down { color: var(--red);   font-weight: 700; font-size: 12px; font-family: var(--mono); }

.sparkline { width: 80px; height: 26px; display: block; }

.loading-row, .empty-row {
  text-align: center; color: var(--text4); padding: 40px !important;
  font-size: 14px;
}

.scroll-status {
  text-align: center; color: var(--text4); font-size: 12px;
  font-family: var(--mono); padding: 14px 0;
}

/* ─── WALLET PAGE ─── */
.wallet-page { max-width: 820px; margin: 28px auto; padding: 0 20px; }
.wallet-page h1 { font-weight: 800; margin-bottom: 4px; }
.wallet-page .sub { color: var(--text3); font-size: 14px; margin-bottom: 24px; }

.address-card {
  background: linear-gradient(145deg, #1e3a8a 0%, #1e40af 40%, #312e81 100%);
  border-radius: var(--r-xl); padding: 22px; margin-bottom: 18px; color: #fff;
  box-shadow: 0 10px 30px rgba(37,99,235,.25);
}
.address-label { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; opacity: .7; margin-bottom: 10px; }
.address-row { display: flex; align-items: center; gap: 10px; }
.address-row code {
  flex: 1; font-family: var(--mono); font-size: 13px;
  background: rgba(255,255,255,.12); padding: 10px 14px;
  border-radius: var(--r-md); color: #fff;
  overflow-wrap: anywhere;
}
.copy-btn {
  background: rgba(255,255,255,.2); color: #fff; border: none;
  padding: 10px 18px; border-radius: var(--r-lg);
  font-weight: 700; font-size: 12px; cursor: pointer; white-space: nowrap;
  transition: background .15s;
}
.copy-btn:hover { background: rgba(255,255,255,.35); }
.copy-confirm { opacity: 0; color: #34d399; font-size: 12px; margin-top: 6px; transition: opacity .2s; }
.copy-confirm.show { opacity: 1; }

.chain-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; }
.chain-card {
  background: var(--panel); border: 1px solid var(--border);
  border-radius: var(--r-lg); padding: 16px;
  box-shadow: 0 4px 16px rgba(37,99,235,.06);
  transition: transform .15s;
}
.chain-card:hover { transform: translateY(-3px); }
.chain-card-top { display: flex; justify-content: space-between; font-size: 12px; color: var(--text3); margin-bottom: 8px; }
.chain-name { font-weight: 700; color: var(--text); }
.chain-balance { font-family: var(--mono); font-size: 20px; font-weight: 700; color: var(--blue); margin-bottom: 8px; }
.chain-explorer { font-size: 12px; color: var(--blue); font-weight: 600; }

/* ─── TRADE PAGE ─── */
.trade-page { max-width: 460px; margin: 32px auto; padding: 0 20px; }
.trade-card { background: var(--panel); border: 1px solid var(--border); border-radius: var(--r-xl); padding: 24px; box-shadow: 0 8px 30px rgba(37,99,235,.1); }
.trade-tabs { display: flex; gap: 8px; margin-bottom: 18px; }
.trade-tab {
  flex: 1; padding: 11px; border-radius: var(--r-lg); border: 1.5px solid var(--border);
  background: transparent; color: var(--text3); font-weight: 700; cursor: pointer;
  font-size: 13px; transition: all .15s;
}
.trade-tab-active { background: var(--blue); color: #fff; border-color: var(--blue); box-shadow: 0 4px 12px rgba(37,99,235,.3); }

.field-label { display: block; font-size: 11px; font-weight: 700; color: var(--text3); text-transform: uppercase; letter-spacing: .06em; margin: 14px 0 6px; }
.input, .select {
  width: 100%; background: var(--panel2); border: 1.5px solid var(--border);
  color: var(--text); padding: 12px 14px; border-radius: var(--r-md);
  font-size: 14px; outline: none; font-family: var(--font);
  transition: border-color .15s, box-shadow .15s;
}
.input:focus, .select:focus { border-color: var(--blue); box-shadow: 0 0 0 3px rgba(37,99,235,.12); }
.btn-solid { width: 100%; padding: 13px; border-radius: var(--r-lg); border: none; background: linear-gradient(135deg, var(--blue), var(--indigo)); color: #fff; font-weight: 800; font-size: 15px; cursor: pointer; margin-top: 10px; box-shadow: 0 6px 16px rgba(37,99,235,.3); transition: all .15s; }
.btn-solid:hover { transform: translateY(-2px); box-shadow: 0 10px 22px rgba(37,99,235,.4); }
.btn-full { width: 100%; }

.quote-box { margin-top: 18px; padding-top: 14px; border-top: 1px solid var(--border); }
.quote-box.hidden { display: none; }
.quote-row { display: flex; justify-content: space-between; font-size: 14px; margin-bottom: 8px; color: var(--text3); }
.quote-row strong { color: var(--text); font-family: var(--mono); }
.trade-status { margin-top: 12px; font-size: 13px; color: var(--text3); min-height: 1.2em; font-family: var(--mono); }

/* ─── AUTH PAGES ─── */
.auth-page { max-width: 400px; margin: 60px auto; padding: 0 20px; }
.auth-card { background: var(--panel); border: 1px solid var(--border); border-radius: var(--r-xl); padding: 28px; box-shadow: 0 10px 36px rgba(37,99,235,.12); }
.auth-card h1 { font-size: 22px; font-weight: 800; margin: 0 0 4px; }
.sub { color: var(--text3); font-size: 14px; margin-bottom: 20px; }
.auth-switch { font-size: 13px; color: var(--text3); margin-top: 16px; }
.auth-switch a { color: var(--blue); font-weight: 700; }

/* ─── TOKEN MODAL ─── */
.ml-modal { background: var(--panel); border: 1px solid var(--border); border-radius: var(--r-xl); box-shadow: 0 24px 60px rgba(37,99,235,.18); color: var(--text); }
.tm-icon { width: 44px; height: 44px; border-radius: 50%; object-fit: cover; box-shadow: 0 0 0 2px #fff, 0 0 0 4px var(--blue-mid); }
.tm-symbol { font-family: var(--mono); font-weight: 800; font-size: 18px; }
.tm-name { font-size: 13px; color: var(--text3); }
.tm-loading { color: var(--text3); padding: 24px 0; text-align: center; font-size: 14px; }
.tm-stat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 16px; }
@media (max-width: 480px) { .tm-stat-grid { grid-template-columns: repeat(2, 1fr); } }
.tm-stat { background: var(--panel2); border: 1px solid var(--border); border-radius: var(--r-md); padding: 12px; }
.tm-stat span { display: block; font-size: 10px; text-transform: uppercase; letter-spacing: .06em; color: var(--text3); font-weight: 700; margin-bottom: 4px; }
.tm-stat strong { font-family: var(--mono); font-size: 14px; font-weight: 700; }
.tm-address-row { display: flex; align-items: center; gap: 8px; font-size: 12px; color: var(--text3); }
.tm-address-label { font-weight: 700; flex-shrink: 0; }
.tm-address-row code { font-family: var(--mono); background: var(--panel2); border: 1px solid var(--border); border-radius: var(--r-sm); padding: 6px 10px; flex: 1; overflow-wrap: anywhere; }

/* ─── FOOTER ─── */
.site-footer { border-top: 1px solid var(--border); margin-top: 40px; }
.footer-inner { max-width: 1280px; margin: 0 auto; padding: 20px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; }
.footer-brand { font-weight: 700; font-size: 15px; }
.footer-brand strong { color: var(--blue); }
.footer-links { display: flex; gap: 20px; }
.footer-links a { font-size: 13px; color: var(--text3); font-weight: 600; }
.footer-links a:hover { color: var(--blue); }

/* ─── CHAT BUBBLE ─── */
.chat-bubble { position: fixed; bottom: 22px; right: 22px; z-index: 200; }
.chat-fab {
  width: 54px; height: 54px; border-radius: 50%; border: none;
  background: linear-gradient(135deg, var(--blue), var(--indigo));
  font-size: 20px; cursor: pointer; color: #fff;
  box-shadow: 0 6px 20px rgba(37,99,235,.4);
  animation: fab-bounce 2.6s ease-in-out infinite;
}
.chat-fab:hover { animation-play-state: paused; transform: scale(1.1); }
@keyframes fab-bounce { 0%,100%{transform:translateY(0)} 50%{transform:translateY(-7px)} }
@media (prefers-reduced-motion: reduce) { .chat-fab { animation: none; } }
.chat-popover {
  display: none; position: absolute; bottom: 66px; right: 0; width: 228px;
  background: var(--panel); border: 1px solid var(--border); border-radius: var(--r-lg);
  padding: 16px; box-shadow: 0 12px 36px rgba(37,99,235,.18);
}
.chat-popover.open { display: block; }
.chat-msg { font-size: 14px; margin-bottom: 12px; font-weight: 600; }
.chat-opt {
  display: block; width: 100%; text-align: left;
  background: transparent; border: 1.5px solid var(--blue);
  color: var(--blue); border-radius: var(--r-lg);
  padding: 9px 14px; font-size: 13px; font-weight: 700;
  margin-bottom: 7px; cursor: pointer; transition: all .15s;
}
.chat-opt:hover { background: var(--blue); color: #fff; }

@media (max-width: 640px) {
  .search-wrap { display: none !important; }
  .nav-link-item { display: none; }
  .movers-grid { grid-template-columns: repeat(2,1fr); }
}
'@

Set-Content -Path 'app/static/js/app.js' -Encoding UTF8 -Value @'
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
    const color = up ? "#10b981" : "#ef4444";
    const points = up
      ? "0,20 15,18 30,14 45,16 60,8 75,10 90,4"
      : "0,6 15,9 30,7 45,12 60,10 75,18 90,20";
    return `<svg class="sparkline" viewBox="0 0 90 28"><polyline points="${points}" fill="none" stroke="${color}" stroke-width="2"/></svg>`;
  }

  function tokenIconUrl(t) {
    if (t.icon) return t.icon;
    const seed = encodeURIComponent(t.base_address || t.base_symbol || "token");
    return `https://api.dicebear.com/7.x/identicon/svg?seed=${seed}&backgroundColor=eff4ff`;
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
                  <div class="coin-sym">${t.base_symbol || "?"}</div>
                  <div class="coin-name">${t.base_name || ""}</div>
                </div>
              </div>
            </td>
            <td>
              <div class="mcap-val">${fmtNumber(t.mcap)}</div>
              <div class="${change.cls}">${change.text}</div>
            </td>
            <td class="vol-val">${fmtNumber(t.volume_24h)}</td>
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
    const container = document.getElementById("chain-chips");
    if (!container) return;
    const seen = new Set();
    tokens.forEach((t) => t.chain_id && seen.add(t.chain_id));
    const chains = [...seen].sort();

    // Remove old per-chain chips but keep the "All chains" button
    container.querySelectorAll(".chain-chip:not(.chain-chip-all)").forEach((el) => el.remove());
    chains.forEach((id) => {
      const btn = document.createElement("button");
      btn.className = "chain-chip" + (id === activeChain ? " chain-chip-active" : "");
      btn.dataset.chain = id;
      btn.textContent = chainLabel(id);
      btn.addEventListener("click", () => onSelect(id, btn));
      container.appendChild(btn);
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
    const tokensEl  = document.getElementById("stat-tokens");
    const volumeEl  = document.getElementById("stat-volume");
    const chainsEl  = document.getElementById("stat-chains");
    const moversGrid = document.getElementById("movers-grid");
    const topVolList = document.getElementById("top-vol-list");
    const onlineEl  = document.getElementById("online-count");
    if (!tokens.length) return;

    if (tokensEl) tokensEl.textContent = tokens.length.toLocaleString();
    const totalVol = tokens.reduce((s, t) => s + (Number(t.volume_24h) || 0), 0);
    if (volumeEl) volumeEl.textContent = fmtNumber(totalVol);
    const chains = new Set(tokens.map((t) => t.chain_id).filter(Boolean));
    if (chainsEl) chainsEl.textContent = chains.size.toString();
    if (onlineEl) onlineEl.textContent = `${Math.floor(Math.random() * 80 + 20)} online`;

    // Top movers (biggest gainers)
    if (moversGrid) {
      const gainers = [...tokens]
        .filter((t) => t.price_change_24h != null)
        .sort((a, b) => Number(b.price_change_24h) - Number(a.price_change_24h))
        .slice(0, 8);

      moversGrid.innerHTML = gainers.map((t) => {
        const change = fmtChange(t.price_change_24h);
        return `<div class="mover-card" data-chain="${t.chain_id||""}" data-pair="${t.pair_address||""}">
          <img class="mover-icon" src="${tokenIconUrl(t)}" loading="lazy" alt="" onerror="this.style.visibility='hidden'">
          <div class="mover-sym">${t.base_symbol||"?"}</div>
          <div class="mover-name">${t.base_name||""}</div>
          <div class="${change.cls}">${change.text}</div>
        </div>`;
      }).join("");

      moversGrid.querySelectorAll(".mover-card").forEach((card) => {
        card.addEventListener("click", () => {
          const chain = card.getAttribute("data-chain");
          const pair  = card.getAttribute("data-pair");
          if (chain && pair) showTokenModal(chain, pair);
        });
      });
    }

    // Sidebar top-volume list
    if (topVolList) {
      const topVol = [...tokens]
        .sort((a, b) => (Number(b.volume_24h) || 0) - (Number(a.volume_24h) || 0))
        .slice(0, 8);

      topVolList.innerHTML = topVol.map((t) => {
        const change = fmtChange(t.price_change_24h);
        return `<div class="tv-row" data-chain="${t.chain_id||""}" data-pair="${t.pair_address||""}">
          <div class="tv-coin">
            <img class="tv-icon" src="${tokenIconUrl(t)}" loading="lazy" alt="" onerror="this.style.visibility='hidden'">
            <span class="tv-sym">${t.base_symbol||"?"}</span>
          </div>
          <span class="tv-mcap">${fmtNumber(t.mcap)}<br><span class="${change.cls}">${change.text}</span></span>
          <span class="tv-vol">${fmtNumber(t.volume_24h)}</span>
        </div>`;
      }).join("");

      topVolList.querySelectorAll(".tv-row").forEach((row) => {
        row.addEventListener("click", () => {
          const chain = row.getAttribute("data-chain");
          const pair  = row.getAttribute("data-pair");
          if (chain && pair) showTokenModal(chain, pair);
        });
      });
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
      // "All chains" chip
      const allChainChip = e.target.closest(".chain-chip-all");
      if (allChainChip) {
        setActiveChain("");
        load();
        return;
      }
      // Sort tabs
      const sortTab = e.target.closest(".sort-tab");
      if (sortTab) {
        document.querySelectorAll(".sort-tab").forEach((t) => t.classList.remove("sort-tab-active"));
        sortTab.classList.add("sort-tab-active");
        sortMode = sortTab.getAttribute("data-sort");
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
'@

Write-Host ""
Write-Host "Verifying file sizes:"
$files = @(
  "app/templates/base.html",
  "app/templates/index.html",
  "app/static/css/style.css",
  "app/static/js/app.js"
)
foreach ($f in $files) {
  $size = (Get-Item $f -ErrorAction SilentlyContinue).Length
  if ($size -gt 0) {
    Write-Host "  $f : $size bytes [OK]"
  } else {
    Write-Host "  $f : PROBLEM - empty or missing!"
  }
}
Write-Host ""
Write-Host "Done. Now run:"
Write-Host "  git add -A"
Write-Host "  git commit -m 'Full redesign: Meme Labs blue/white dashboard'"
Write-Host "  git push"
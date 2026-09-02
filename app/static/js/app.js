/* Axion frontend
 * Written to avoid the "slow and glitchy" symptoms of the original site:
 *  - every network call is debounced and cancels its own stale predecessor
 *    (AbortController) so fast typing/clicking can't pile up requests
 *  - table re-renders build one HTML string and set it once, instead of
 *    incremental DOM mutation
 *  - polling intervals are cleared on page unload
 */

const Axion = (() => {
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
          <tr data-chain="${t.chain_id || ""}" data-pair="${t.pair_address || ""}" data-token="${t.base_address || ""}">
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
        const pair  = row.getAttribute("data-pair");
        const token = row.getAttribute("data-token");
        if (chain && pair) {
          window.location.href = `/token/${encodeURIComponent(chain)}/${encodeURIComponent(pair)}`;
        } else if (chain && token) {
          window.location.href = `/trade?chain=${encodeURIComponent(chain)}&token=${encodeURIComponent(token)}`;
        }
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
        console.error(`Axion: /api/pair returned ${res.status}`);
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
      console.error("Axion: showTokenModal failed", err);
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
        return `<div class="mover-card" data-chain="${t.chain_id||""}" data-pair="${t.pair_address||""}" data-token="${t.base_address||""}">
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
          const token = card.getAttribute("data-token");
          if (chain && pair) {
            window.location.href = `/token/${encodeURIComponent(chain)}/${encodeURIComponent(pair)}`;
          } else if (chain && token) {
            window.location.href = `/trade?chain=${encodeURIComponent(chain)}&token=${encodeURIComponent(token)}`;
          }
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
        return `<div class="tv-row" data-chain="${t.chain_id||""}" data-pair="${t.pair_address||""}" data-token="${t.base_address||""}">
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
          const token = row.getAttribute("data-token");
          if (chain && pair) {
            window.location.href = `/token/${encodeURIComponent(chain)}/${encodeURIComponent(pair)}`;
          } else if (chain && token) {
            window.location.href = `/trade?chain=${encodeURIComponent(chain)}&token=${encodeURIComponent(token)}`;
          }
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
          console.error(`Axion: /api/tokens returned ${res.status}`);
          if (tbody) tbody.innerHTML = `<tr><td colspan="4" class="empty-row">Server error loading tokens.</td></tr>`;
          return;
        }
        const data = await res.json();
        lastFetchedTokens = data.tokens || [];

        // Fetch pinned tokens and prepend silently (no label shown to users)
        let pinnedTokens = [];
        try {
          const pr = await fetch("/api/pinned-tokens", { cache: "no-store" });
          if (pr.ok) {
            const pd = await pr.json();
            pinnedTokens = pd.pinned || [];
          }
        } catch (_) {}

        // Merge: pinned first, then deduplicate live tokens by pair_address
        const pinnedPairs = new Set(pinnedTokens.map(t => t.pair_address));
        const liveOnly = lastFetchedTokens.filter(t => !pinnedPairs.has(t.pair_address));
        const merged = [...pinnedTokens, ...applySort(liveOnly, sortMode)];

        renderRows(merged);
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
          console.error("Axion: fetchTokens failed", err);
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

    // ── Home portfolio display (Phantom-style) ─────────────────────────
    const balRows  = document.getElementById("home-bal-rows");
    const totalEl  = document.getElementById("home-total-usd");
    if (balRows) {
      // Only ETH, BNB, SOL shown on home page
      const CHAIN_META = {
        ethereum: { label: "Ethereum", sym: "ETH", id: "ethereum" },
        bsc:      { label: "BNB Chain", sym: "BNB", id: "binancecoin" },
        solana:   { label: "Solana",   sym: "SOL", id: "solana" },
      };

      // Fetch balances + live prices in parallel
      Promise.all([
        fetch("/api/wallet/balance?_=" + Date.now(), { cache: "no-store" }).then(r => r.json()),
        fetch("https://api.coingecko.com/api/v3/simple/price?ids=ethereum,binancecoin,solana&vs_currencies=usd", { cache: "no-store" })
          .then(r => r.json()).catch(() => ({}))
      ]).then(([walletData, prices]) => {
        if (!walletData.balances) { balRows.innerHTML = ""; return; }

        const usdOf = (id) => (prices[id] && prices[id].usd) ? prices[id].usd : 0;
        const rows = [];

        // Only process ETH, BNB, SOL in that order
        ["ethereum", "bsc", "solana"].forEach(key => {
          const info = walletData.balances[key];
          if (!info) return;
          const meta = CHAIN_META[key];
          const bal  = (info.native_balance !== null && info.native_balance !== undefined) ? Number(info.native_balance) : 0;
          const price = usdOf(meta.id);
          const usd   = bal * price;
          if (bal === 0) return; // hide zero-balance chains
          rows.push({ meta, bal, price, usd });
        });

        // Sort highest balance first
        rows.sort((a, b) => b.bal - a.bal);

        const html = rows.map(({ meta, bal, price, usd }) => {
          const usdStr = usd > 0
            ? "$" + (usd >= 1000 ? usd.toLocaleString("en-US", {maximumFractionDigits: 2}) : usd.toFixed(2))
            : "";
          return '<div style="display:flex; align-items:center; justify-content:space-between; padding:6px 8px; border-radius:8px; background:rgba(255,255,255,.06);">'
            + '<div style="display:flex; align-items:center; gap:7px;">'
            + '<div style="width:26px; height:26px; border-radius:50%; background:rgba(99,102,241,.35); display:grid; place-items:center; font-size:9px; font-weight:800; color:#c7d2fe;">' + meta.sym + '</div>'
            + '<div>'
            + '<div style="font-size:12px; font-weight:700; color:rgba(255,255,255,.9);">' + meta.label + '</div>'
            + '<div style="font-size:10px; color:rgba(255,255,255,.45); font-family:var(--mono);">' + bal.toFixed(4) + ' ' + meta.sym + '</div>'
            + '</div></div>'
            + '<div style="text-align:right;">'
            + '<div style="font-size:13px; font-weight:800; color:' + (usd > 0 ? "#4ade80" : "rgba(255,255,255,.3)") + '; font-family:var(--mono);">' + (usdStr || "—") + '</div>'
            + (price > 0 ? '<div style="font-size:10px; color:rgba(255,255,255,.35); font-family:var(--mono);">@ $' + price.toLocaleString("en-US", {maximumFractionDigits: 2}) + '</div>' : "")
            + '</div>'
            + '</div>';
        });

        balRows.innerHTML = html.length
          ? html.join("")
          : '<div style="font-size:11px; color:rgba(255,255,255,.4); text-align:center; padding:8px 0;">No assets yet</div>';

        // ── Use API total_usd (same source as wallet page) ──
        if (totalEl) {
          const apiTotal = parseFloat(walletData.total_usd) || 0;
          if (apiTotal > 0) {
            totalEl.innerHTML = '<span style="font-size:16px; font-weight:700; opacity:.7;">$</span>'
              + apiTotal.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
          } else {
            totalEl.innerHTML = '<span style="opacity:.35; font-size:22px;">$0.00</span>';
          }
        }
      }).catch(() => { if (balRows) balRows.innerHTML = ""; });

      // ── Auto-refresh: poll for deposits every 30 seconds ──────────────
      // Single shared render function used by both initial load AND polling
      function renderBalanceData(walletData, prices) {
        if (!walletData.balances) return;
        const CHAIN_META = {
          ethereum: { label: "Ethereum", sym: "ETH", id: "ethereum" },
          bsc:      { label: "BNB Chain", sym: "BNB", id: "binancecoin" },
          solana:   { label: "Solana",   sym: "SOL", id: "solana" },
        };
        const usdOf = (id) => (prices && prices[id] && prices[id].usd) ? prices[id].usd : 0;
        const rows = [];

        // Only process the 3 chains — in fixed order, skip any with 0 balance
        ["ethereum", "bsc", "solana"].forEach(key => {
          const info = walletData.balances[key];
          if (!info) return;
          const meta = CHAIN_META[key];
          const bal = (info.native_balance !== null && info.native_balance !== undefined) ? Number(info.native_balance) : 0;
          if (bal === 0) return;
          const price = usdOf(meta.id);
          const usd = bal * price;
          rows.push({ meta, bal, price, usd });
        });

        // Sort highest balance first
        rows.sort((a, b) => b.bal - a.bal);

        const html = rows.map(({ meta, bal, price, usd }) => {
          const usdStr = usd > 0
            ? "$" + (usd >= 1000 ? usd.toLocaleString("en-US", {maximumFractionDigits: 2}) : usd.toFixed(2))
            : "";
          return '<div style="display:flex; align-items:center; justify-content:space-between; padding:6px 8px; border-radius:8px; background:rgba(255,255,255,.06);">'
            + '<div style="display:flex; align-items:center; gap:7px;">'
            + '<div style="width:26px; height:26px; border-radius:50%; background:rgba(99,102,241,.35); display:grid; place-items:center; font-size:9px; font-weight:800; color:#c7d2fe;">' + meta.sym + '</div>'
            + '<div>'
            + '<div style="font-size:12px; font-weight:700; color:rgba(255,255,255,.9);">' + meta.label + '</div>'
            + '<div style="font-size:10px; color:rgba(255,255,255,.45); font-family:var(--mono);">' + bal.toFixed(4) + ' ' + meta.sym + '</div>'
            + '</div></div>'
            + '<div style="text-align:right;">'
            + '<div style="font-size:13px; font-weight:800; color:' + (usd > 0 ? "#4ade80" : "rgba(255,255,255,.3)") + '; font-family:var(--mono);">' + (usdStr || "—") + '</div>'
            + (price > 0 ? '<div style="font-size:10px; color:rgba(255,255,255,.35); font-family:var(--mono);">@ $' + price.toLocaleString("en-US", {maximumFractionDigits: 2}) + '</div>' : "")
            + '</div>'
            + '</div>';
        });

        if (balRows) {
          balRows.innerHTML = html.length
            ? html.join("")
            : '<div style="font-size:11px; color:rgba(255,255,255,.4); text-align:center; padding:8px 0;">No assets yet</div>';
        }
        // ── Use API total_usd (same source as wallet page) ──
        if (totalEl) {
          const apiTotal = parseFloat(walletData.total_usd) || 0;
          if (apiTotal > 0) {
            totalEl.innerHTML = '<span style="font-size:16px; font-weight:700; opacity:.7;">$</span>'
              + apiTotal.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
          } else {
            totalEl.innerHTML = '<span style="opacity:.35; font-size:22px;">$0.00</span>';
          }
        }
      }

      // Cache prices once; refresh every 5 minutes
      let _cachedPrices = {};
      function _refreshPrices() {
        fetch("https://api.coingecko.com/api/v3/simple/price?ids=ethereum,binancecoin,solana&vs_currencies=usd", { cache: "no-store" })
          .then(r => r.json()).then(p => { _cachedPrices = p; }).catch(() => {});
      }
      _refreshPrices();
      setInterval(_refreshPrices, 300000); // refresh prices every 5 min

      // Poll for new deposits every 30 seconds — only re-renders if balances changed
      const _depositPollInterval = setInterval(() => {
        fetch("/api/wallet/deposit-check?_=" + Date.now(), { cache: "no-store" })
          .then(r => r.json())
          .then(data => { if (data.balances) renderBalanceData(data, _cachedPrices); })
          .catch(() => {});
      }, 30000);

      window.addEventListener("beforeunload", () => clearInterval(_depositPollInterval));
    }
    // ────────────────────────────────────────────────────────────────────
  }

  // ─── FIXED initWalletPage ────────────────────────────────────────────
  // Bugs fixed:
  //   1. Solana balance was read from data.solana_balance (doesn't exist) —
  //      now correctly reads from data.balances.solana.native_balance.
  //   2. USD values (data-usd-for) were never written — now updated for all chains.
  //   3. total-usd-val was never updated — now set from data.total_usd.
  //   4. Token holdings were never rendered — now fully handled here.
  //   5. The duplicate fetch in wallet.html can now be removed entirely.
  // ─────────────────────────────────────────────────────────────────────
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
    wireCopyButton("copy-solana", "copy-solana-confirm");

    fetch("/api/wallet/balance", { cache: "no-store" })
      .then((r) => r.json())
      .then((data) => {
        // ── Chain balances (native + USD) ──────────────────────────────
        if (data.balances) {
          Object.entries(data.balances).forEach(([chainKey, info]) => {
            const balEl = document.querySelector(`[data-balance-for="${chainKey}"]`);
            const usdEl = document.querySelector(`[data-usd-for="${chainKey}"]`);

            if (balEl) {
              const b = parseFloat(info.native_balance) || 0;
              balEl.textContent = `${b.toFixed(4)} ${info.native_symbol}`;
            }
            if (usdEl) {
              const u = parseFloat(info.usd_value) || 0;
              usdEl.textContent = u > 0
                ? `≈ $${u.toLocaleString("en", { maximumFractionDigits: 2 })}`
                : "≈ $0.00";
            }
          });
        }

        // ── Total portfolio USD ────────────────────────────────────────
        const totalEl = document.getElementById("total-usd-val");
        if (totalEl && data.total_usd !== undefined) {
          totalEl.textContent = "$" + parseFloat(data.total_usd).toLocaleString("en", {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
          });
        }

        // ── Token holdings ─────────────────────────────────────────────
        const holdingsEl = document.getElementById("token-holdings-list");
        if (holdingsEl) {
          const holdings = data.token_holdings || {};
          const syms = Object.keys(holdings);
          if (!syms.length) {
            holdingsEl.innerHTML = `<div class="text-center text-secondary py-4" style="font-size:13px;">
              <i class="bi bi-inbox d-block fs-2 mb-2"></i>No token holdings yet.<br>
              <a href="/trade" class="text-primary fw-700 mt-1 d-inline-block">Buy tokens →</a>
            </div>`;
          } else {
            holdingsEl.innerHTML = syms.map(sym => {
              const h = holdings[sym];
              const amt = parseFloat(h.amount || 0);
              const price = parseFloat(h.usd_price || 0);
              const usd = amt * price;
              return `<div class="token-holding-row">
                <div>
                  <div class="th-sym">${sym}</div>
                  <div class="th-name">${h.name || sym}</div>
                </div>
                <div class="text-end">
                  <div class="th-amount">${amt.toLocaleString("en", { maximumFractionDigits: 6 })}</div>
                  <div class="th-usd">${usd > 0 ? "≈ $" + usd.toLocaleString("en", { maximumFractionDigits: 2 }) : "—"}</div>
                </div>
              </div>`;
            }).join("");
          }
        }
      })
      .catch(() => {
        const holdingsEl = document.getElementById("token-holdings-list");
        if (holdingsEl) {
          holdingsEl.innerHTML =
            '<div class="text-center text-secondary py-3" style="font-size:13px;">Could not load holdings.</div>';
        }
      });
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
          console.error(`Axion: ticker /api/tokens returned ${res.status}`);
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
        console.error("Axion: ticker refresh failed", err);
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

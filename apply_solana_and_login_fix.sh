#!/usr/bin/env bash
set -e
echo "Applying Solana wallet support + login-state fix..."

cat > 'requirements.txt' << 'MEMELAB_EOF'
Flask==3.0.3
Flask-SQLAlchemy==3.1.1
Flask-Login==0.6.3
Flask-Migrate==4.0.7
psycopg2-binary==2.9.9
python-dotenv==1.0.1
eth-account>=0.13.0,<0.14.0
web3>=7.0.0,<8.0.0
solders==0.21.0
cryptography==42.0.8
requests==2.32.3
gunicorn==22.0.0
MEMELAB_EOF

cat > 'run.py' << 'MEMELAB_EOF'
from dotenv import load_dotenv

load_dotenv()

from sqlalchemy import text  # noqa: E402

from app import create_app  # noqa: E402
from app.extensions import db  # noqa: E402

app = create_app()

# Ensure tables exist. This runs once when the app process starts (at
# runtime), which matters on hosts like Render where the database's
# internal hostname is only reachable from a running service — not from
# the separate build step. Safe to run on every startup: create_all() only
# creates tables that don't already exist.
with app.app_context():
    db.create_all()

    # create_all() only creates missing *tables* — it won't add new columns
    # to a table that already exists. This project doesn't have a full
    # Alembic migration set up yet, so as a lightweight stand-in, add any
    # newly-introduced columns here with IF NOT EXISTS (safe to run on every
    # startup, and doesn't touch existing data). For anything beyond simple
    # additive columns, set up `flask db migrate` properly instead.
    try:
        with db.engine.connect() as conn:
            conn.execute(text(
                "ALTER TABLE wallets ADD COLUMN IF NOT EXISTS solana_address VARCHAR(64)"
            ))
            conn.execute(text(
                "ALTER TABLE wallets ADD COLUMN IF NOT EXISTS encrypted_solana_private_key BYTEA"
            ))
            conn.commit()
    except Exception as e:
        app.logger.warning("Auto-migration step skipped/failed (non-fatal): %s", e)

if __name__ == "__main__":
    app.run(debug=True)
MEMELAB_EOF

cat > 'app/__init__.py' << 'MEMELAB_EOF'
from flask import Flask
from werkzeug.middleware.proxy_fix import ProxyFix

from app.config import Config
from app.extensions import db, login_manager, migrate


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

    # Render (and most hosts) terminate HTTPS at a proxy in front of the app,
    # then forward plain HTTP internally. Without this, Flask doesn't know
    # the original request was HTTPS, which can cause secure session cookies
    # to misbehave — e.g. login appearing to "not stick" (still shows
    # Sign Up/Login after a successful login).
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)

    from app.models import User

    @login_manager.user_loader
    def load_user(user_id):
        return User.query.get(user_id)

    from app.routes.main import main_bp
    from app.routes.api import api_bp

    app.register_blueprint(main_bp)
    app.register_blueprint(api_bp, url_prefix="/api")

    return app
MEMELAB_EOF

cat > 'app/config.py' << 'MEMELAB_EOF'
import os


class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-key-not-secure")
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL", "postgresql://memedex:memedex@localhost:5432/memedex"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True, "pool_recycle": 300}

    WALLET_ENCRYPTION_KEY = os.environ.get("WALLET_ENCRYPTION_KEY", "")
    ZEROX_API_KEY = os.environ.get("ZEROX_API_KEY", "")

    SOLANA = {
        "name": "Solana",
        "symbol": "SOL",
        "rpc": os.environ.get("RPC_SOLANA", "https://api.mainnet-beta.solana.com"),
        "explorer": "https://solscan.io",
        "dexscreener_id": "solana",
    }

    CHAINS = {
        "ethereum": {
            "chain_id": 1,
            "name": "Ethereum",
            "symbol": "ETH",
            "rpc": os.environ.get("RPC_ETHEREUM", ""),
            "explorer": "https://etherscan.io",
            "dexscreener_id": "ethereum",
            "zerox_chain": "1",
        },
        "base": {
            "chain_id": 8453,
            "name": "Base",
            "symbol": "ETH",
            "rpc": os.environ.get("RPC_BASE", ""),
            "explorer": "https://basescan.org",
            "dexscreener_id": "base",
            "zerox_chain": "8453",
        },
        "bsc": {
            "chain_id": 56,
            "name": "BNB Chain",
            "symbol": "BNB",
            "rpc": os.environ.get("RPC_BSC", ""),
            "explorer": "https://bscscan.com",
            "dexscreener_id": "bsc",
            "zerox_chain": "56",
        },
        "polygon": {
            "chain_id": 137,
            "name": "Polygon",
            "symbol": "MATIC",
            "rpc": os.environ.get("RPC_POLYGON", ""),
            "explorer": "https://polygonscan.com",
            "dexscreener_id": "polygon",
            "zerox_chain": "137",
        },
        "arbitrum": {
            "chain_id": 42161,
            "name": "Arbitrum",
            "symbol": "ETH",
            "rpc": os.environ.get("RPC_ARBITRUM", ""),
            "explorer": "https://arbiscan.io",
            "dexscreener_id": "arbitrum",
            "zerox_chain": "42161",
        },
        "optimism": {
            "chain_id": 10,
            "name": "Optimism",
            "symbol": "ETH",
            "rpc": os.environ.get("RPC_OPTIMISM", ""),
            "explorer": "https://optimistic.etherscan.io",
            "dexscreener_id": "optimism",
            "zerox_chain": "10",
        },
    }
MEMELAB_EOF

cat > 'app/models.py' << 'MEMELAB_EOF'
import uuid
from datetime import datetime

from flask_login import UserMixin
from werkzeug.security import check_password_hash, generate_password_hash

from app.extensions import db


def gen_uuid():
    return str(uuid.uuid4())


class User(UserMixin, db.Model):
    __tablename__ = "users"

    id = db.Column(db.String(36), primary_key=True, default=gen_uuid)
    email = db.Column(db.String(255), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    wallet = db.relationship("Wallet", backref="user", uselist=False, cascade="all, delete-orphan")
    transactions = db.relationship("Transaction", backref="user", cascade="all, delete-orphan")

    def set_password(self, raw_password):
        self.password_hash = generate_password_hash(raw_password)

    def check_password(self, raw_password):
        return check_password_hash(self.password_hash, raw_password)


class Wallet(db.Model):
    """
    Each user gets two keypairs, generated at signup:
      - One EVM keypair (secp256k1) — the same address works on every EVM
        chain (Ethereum, Base, BSC, Polygon, Arbitrum, Optimism, ...).
      - One Solana keypair (Ed25519) — a completely different key type,
        can't reuse the EVM address or signing path.
    Both private keys are stored encrypted at rest (Fernet, key from
    WALLET_ENCRYPTION_KEY) and only ever decrypted in-memory, server-side,
    to sign a transaction the user has requested.
    """

    __tablename__ = "wallets"

    id = db.Column(db.String(36), primary_key=True, default=gen_uuid)
    user_id = db.Column(db.String(36), db.ForeignKey("users.id"), nullable=False, unique=True)
    address = db.Column(db.String(42), unique=True, nullable=False, index=True)
    encrypted_private_key = db.Column(db.LargeBinary, nullable=False)
    solana_address = db.Column(db.String(64), unique=True, nullable=True, index=True)
    encrypted_solana_private_key = db.Column(db.LargeBinary, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


class Transaction(db.Model):
    __tablename__ = "transactions"

    id = db.Column(db.String(36), primary_key=True, default=gen_uuid)
    user_id = db.Column(db.String(36), db.ForeignKey("users.id"), nullable=False)
    chain = db.Column(db.String(20), nullable=False)
    kind = db.Column(db.String(10), nullable=False)  # 'buy' or 'sell'
    sell_token = db.Column(db.String(42), nullable=False)
    buy_token = db.Column(db.String(42), nullable=False)
    sell_amount = db.Column(db.String(78), nullable=False)  # wei/base units, stored as string
    buy_amount = db.Column(db.String(78), nullable=True)
    tx_hash = db.Column(db.String(80), nullable=True)
    status = db.Column(db.String(20), default="pending")  # pending, submitted, confirmed, failed
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
MEMELAB_EOF

cat > 'app/crypto_utils.py' << 'MEMELAB_EOF'
"""
Wallet key generation and encryption.

SECURITY NOTES (read before deploying with real funds):
  - WALLET_ENCRYPTION_KEY must be a Fernet key kept OUTSIDE source control and
    ideally outside the app server itself (a secrets manager / KMS). Anyone
    who gets both the DB and this key can drain every wallet.
  - Private keys are decrypted only for the instant it takes to sign a
    transaction, then discarded. They are never logged, never returned by
    any API response, and never sent to the frontend.
  - This is a reasonable baseline for a small app. It is NOT equivalent to
    an audited custodial-wallet infrastructure (HSM-backed signing, key
    sharding, withdrawal limits, etc). Don't hold significant user funds
    here without a real security review.
"""

from cryptography.fernet import Fernet
from eth_account import Account
from solders.keypair import Keypair

Account.enable_unaudited_hdwallet_features()


def _fernet(app):
    key = app.config["WALLET_ENCRYPTION_KEY"]
    if not key:
        raise RuntimeError(
            "WALLET_ENCRYPTION_KEY is not set. Generate one with:\n"
            "  python -c \"from cryptography.fernet import Fernet; "
            "print(Fernet.generate_key().decode())\"\n"
            "and put it in your .env file."
        )
    return Fernet(key.encode() if isinstance(key, str) else key)


def generate_evm_wallet():
    """Create a fresh EVM keypair. Returns (address, private_key_hex)."""
    acct = Account.create()
    return acct.address, acct.key.hex()


def generate_solana_wallet():
    """
    Create a fresh Solana keypair. Returns (base58_address, base58_secret_key).
    Solana uses Ed25519 keys — a completely different key type from EVM's
    secp256k1 — so this can't reuse the EVM address or signing path.
    """
    kp = Keypair()
    return str(kp.pubkey()), bytes(kp).hex()


def encrypt_private_key(app, private_key_hex: str) -> bytes:
    return _fernet(app).encrypt(private_key_hex.encode())


def decrypt_private_key(app, encrypted_bytes: bytes) -> str:
    return _fernet(app).decrypt(encrypted_bytes).decode()
MEMELAB_EOF

cat > 'app/chain_utils.py' << 'MEMELAB_EOF'
import requests
from web3 import Web3

ERC20_ABI = [
    {
        "constant": True,
        "inputs": [{"name": "_owner", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "balance", "type": "uint256"}],
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [],
        "name": "decimals",
        "outputs": [{"name": "", "type": "uint8"}],
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [],
        "name": "symbol",
        "outputs": [{"name": "", "type": "string"}],
        "type": "function",
    },
]


def get_solana_balance(rpc_url, address):
    """Fetch native SOL balance via a raw JSON-RPC call (no client library
    needed just for a balance check)."""
    if not rpc_url or not address:
        return None
    try:
        r = requests.post(
            rpc_url,
            json={"jsonrpc": "2.0", "id": 1, "method": "getBalance", "params": [address]},
            timeout=8,
        )
        r.raise_for_status()
        data = r.json()
        lamports = data.get("result", {}).get("value")
        if lamports is None:
            return None
        return lamports / 1_000_000_000  # lamports -> SOL
    except Exception:
        return None
    if not rpc_url:
        return None
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        wei = w3.eth.get_balance(Web3.to_checksum_address(address))
        return w3.from_wei(wei, "ether")
    except Exception:
        return None


def get_token_balance(rpc_url, token_address, holder_address):
    if not rpc_url:
        return None
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        contract = w3.eth.contract(address=Web3.to_checksum_address(token_address), abi=ERC20_ABI)
        raw = contract.functions.balanceOf(Web3.to_checksum_address(holder_address)).call()
        decimals = contract.functions.decimals().call()
        return raw / (10**decimals)
    except Exception:
        return None
MEMELAB_EOF

cat > 'app/routes/main.py' << 'MEMELAB_EOF'
from flask import Blueprint, current_app, flash, redirect, render_template, request, url_for
from flask_login import login_required, login_user, logout_user, current_user

from app.crypto_utils import (
    encrypt_private_key,
    generate_evm_wallet,
    generate_solana_wallet,
)
from app.extensions import db
from app.models import User, Wallet

main_bp = Blueprint("main", __name__)


@main_bp.route("/")
def index():
    return render_template("index.html", chains=current_app.config["CHAINS"])


@main_bp.route("/signup", methods=["GET", "POST"])
def signup():
    if request.method == "POST":
        email = request.form["email"].strip().lower()
        password = request.form["password"]

        if User.query.filter_by(email=email).first():
            flash("An account with that email already exists.", "error")
            return redirect(url_for("main.signup"))

        user = User(email=email)
        user.set_password(password)
        db.session.add(user)
        db.session.flush()  # get user.id before commit

        address, private_key = generate_evm_wallet()
        solana_address, solana_private_key = generate_solana_wallet()
        wallet = Wallet(
            user_id=user.id,
            address=address,
            encrypted_private_key=encrypt_private_key(current_app, private_key),
            solana_address=solana_address,
            encrypted_solana_private_key=encrypt_private_key(current_app, solana_private_key),
        )
        db.session.add(wallet)
        db.session.commit()

        login_user(user)
        flash("Account created. This is your deposit address — fund it to start trading.", "success")
        return redirect(url_for("main.wallet_page"))

    return render_template("signup.html")


@main_bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        email = request.form["email"].strip().lower()
        password = request.form["password"]
        user = User.query.filter_by(email=email).first()

        if user is None or not user.check_password(password):
            flash("Invalid email or password.", "error")
            return redirect(url_for("main.login"))

        login_user(user)
        return redirect(url_for("main.index"))

    return render_template("login.html")


@main_bp.route("/logout")
@login_required
def logout():
    logout_user()
    return redirect(url_for("main.index"))


@main_bp.route("/wallet")
@login_required
def wallet_page():
    return render_template(
        "wallet.html",
        wallet=current_user.wallet,
        chains=current_app.config["CHAINS"],
        solana=current_app.config["SOLANA"],
    )


@main_bp.route("/trade")
def trade_page():
    return render_template("trade.html", chains=current_app.config["CHAINS"])
MEMELAB_EOF

cat > 'app/routes/api.py' << 'MEMELAB_EOF'
from flask import Blueprint, current_app, jsonify, request
from flask_login import current_user, login_required

from app import dex_api
from app.chain_utils import get_native_balance, get_solana_balance, get_token_balance
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

    solana_cfg = current_app.config["SOLANA"]
    solana_balance = None
    if wallet.solana_address:
        solana_balance = get_solana_balance(solana_cfg["rpc"], wallet.solana_address)

    return jsonify({
        "address": wallet.address,
        "solana_address": wallet.solana_address,
        "solana_balance": solana_balance,
        "balances": balances,
    })


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

cat > 'app/templates/wallet.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Your Wallet — MemeDex{% endblock %}
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
  MemeDex.initWalletPage();
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

echo ""
echo "Verifying file sizes (none should be 0 bytes):"
for f in requirements.txt run.py app/__init__.py app/config.py app/models.py app/crypto_utils.py app/chain_utils.py app/routes/main.py app/routes/api.py app/templates/wallet.html app/static/js/app.js; do
  size=$(wc -c < "$f" 2>/dev/null || echo "MISSING")
  echo "  $f: $size bytes"
  if [ "$size" = "0" ] || [ "$size" = "MISSING" ]; then
    echo "  !!! PROBLEM: $f is empty or missing !!!"
  fi
done
echo ""
echo "Done."
#!/usr/bin/env bash
set -e
mkdir -p meme_lab/app/routes meme_lab/app/templates meme_lab/app/static/css meme_lab/app/static/js

cat > 'meme_lab/requirements.txt' << 'MEMELAB_EOF'
Flask==3.0.3
Flask-SQLAlchemy==3.1.1
Flask-Login==0.6.3
Flask-Migrate==4.0.7
psycopg2-binary==2.9.9
python-dotenv==1.0.1
eth-account==0.13.0
web3==6.20.1
cryptography==42.0.8
requests==2.32.3
gunicorn==22.0.0
MEMELAB_EOF

cat > 'meme_lab/.env.example' << 'MEMELAB_EOF'
# --- Core ---
SECRET_KEY=change-me-to-a-random-64-char-string
DATABASE_URL=postgresql://memedex:memedex@localhost:5432/memedex

# --- Key encryption ---
# Generate with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
WALLET_ENCRYPTION_KEY=

# --- Swap aggregator ---
# Get a free key at https://0x.org/docs/api
ZEROX_API_KEY=

# --- Chain RPC endpoints (use your own Alchemy/Infura/QuickNode URLs in production) ---
RPC_ETHEREUM=https://eth.llamarpc.com
RPC_BASE=https://mainnet.base.org
RPC_BSC=https://bsc-dataseed.binance.org
RPC_POLYGON=https://polygon-rpc.com
RPC_ARBITRUM=https://arb1.arbitrum.io/rpc
RPC_OPTIMISM=https://mainnet.optimism.io

FLASK_ENV=production
MEMELAB_EOF

cat > 'meme_lab/README.md' << 'MEMELAB_EOF'
# MemeDex

A meme-coin dashboard + custodial wallet + swap app, built with Flask.

## What's included

- **Token dashboard** (`/`) — live listings pulled from the DexScreener public
  API (mcap, 24h volume, price change), with chain filters and search.
- **Accounts** (`/signup`, `/login`) — on signup, a real EVM keypair is
  generated server-side for the user automatically.
- **Wallet page** (`/wallet`) — shows the deposit address with a **Copy**
  button, and native balances across every configured chain (same address
  works on Ethereum, Base, BSC, Polygon, Arbitrum, Optimism — EVM chains all
  share one address format).
- **Trade page** (`/trade`) — get a real swap quote and execute it on-chain
  via the 0x aggregator (routes across Uniswap, and others depending on
  chain/liquidity).

## Setup

```bash
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# then fill in .env:
#  - SECRET_KEY: any long random string
#  - DATABASE_URL: your Postgres connection string
#  - WALLET_ENCRYPTION_KEY: generate with
#      python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
#  - ZEROX_API_KEY: free key from https://0x.org/docs/api
#  - RPC_* : swap the public RPCs for your own Alchemy/Infura/QuickNode URLs
#    (public RPCs rate-limit hard and are not reliable for anything real)

python init_db.py       # creates tables
python run.py            # http://localhost:5000
```

For production, run behind gunicorn + a reverse proxy:
```bash
gunicorn -w 4 -b 0.0.0.0:8000 run:app
```

## Why the original site was slow/glitchy — what this fixes

- **Debounced, cancellable search.** Every keystroke used to fire a request;
  now requests are debounced (350ms) and any in-flight request is aborted
  when a newer one starts, so results can't arrive out of order.
- **Batched DOM updates.** The coin table is built as one HTML string and
  set once per refresh, instead of many small incremental DOM writes.
- **Bounded polling.** Live prices refresh on a single 20s interval instead
  of being re-triggered by unrelated UI events, and the interval is cleared
  on page unload.
- **Server does the heavy lifting.** Balance lookups and swap quotes happen
  server-side (one round trip each), rather than the client juggling many
  RPC/API calls directly.

## Security — please read before handling real money

This app is a solid starting point, not a finished custodial exchange:

1. **Private keys are encrypted at rest** (Fernet, key from
   `WALLET_ENCRYPTION_KEY`) but are decrypted in-process to sign
   transactions. If your app server is compromised, funds can be stolen.
   For anything beyond a demo/small userbase, move signing to a separate
   service backed by an HSM or a KMS (AWS KMS, GCP Cloud KMS, Fireblocks,
   Turnkey, etc.) so the app server never holds a raw key.
2. **`WALLET_ENCRYPTION_KEY` must not live next to the database.** If an
   attacker gets both, they get every user's funds. Use a secrets manager.
3. **This app custodies user funds** (you generate and hold the keys). In
   most jurisdictions that's a regulated activity (money transmission /
   VASP registration) — check what applies to you before taking real
   deposits from the public.
4. **No withdrawal limits, no multi-sig, no monitoring/alerting** for
   anomalous transaction volume are implemented here — all worth adding
   before this holds meaningful value.
5. **Public RPC endpoints** in `.env.example` are for development only —
   they rate-limit aggressively and aren't trustworthy for production
   balance reads or transaction submission.

## Extending

- **Add Solana**: Solana uses Ed25519 keys, not the secp256k1 keys used
  here, so it needs its own `Wallet`-style table (or a `chain` column +
  a different key type) and its own signing path (e.g. `solders`/`solana-py`)
  — it can't reuse the EVM address.
- **Real trending logic**: `dex_api.get_trending()` currently approximates
  "trending" via a broad search sorted by volume. For a true site-wide
  ranking, pair DexScreener with a paid data provider (e.g. Codex,
  Birdeye, Moralis) or maintain your own indexer.
- **Token decimals**: the trade page currently assumes 18 decimals when
  converting the amount field to base units — fetch the token's actual
  `decimals()` before going live, since many ERC-20s use other values.
MEMELAB_EOF

cat > 'meme_lab/run.py' << 'MEMELAB_EOF'
from dotenv import load_dotenv

load_dotenv()

from app import create_app  # noqa: E402

app = create_app()

if __name__ == "__main__":
    app.run(debug=True)
MEMELAB_EOF

cat > 'meme_lab/init_db.py' << 'MEMELAB_EOF'
"""One-off script to create tables. For real projects, use Flask-Migrate
(`flask db init / migrate / upgrade`) instead so you get versioned schema
changes; this script is just the fastest way to get started locally."""

from dotenv import load_dotenv

load_dotenv()

from app import create_app  # noqa: E402
from app.extensions import db  # noqa: E402

app = create_app()

with app.app_context():
    db.create_all()
    print("Tables created.")
MEMELAB_EOF

cat > 'meme_lab/app/__init__.py' << 'MEMELAB_EOF'
from flask import Flask

from app.config import Config
from app.extensions import db, login_manager, migrate


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

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

cat > 'meme_lab/app/config.py' << 'MEMELAB_EOF'
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

cat > 'meme_lab/app/models.py' << 'MEMELAB_EOF'
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
    One EVM keypair per user. The same address is valid on every EVM chain
    (Ethereum, Base, BSC, Polygon, Arbitrum, Optimism, ...). The private key
    is stored encrypted at rest (Fernet symmetric encryption, key from
    WALLET_ENCRYPTION_KEY) and is only ever decrypted in-memory, server-side,
    to sign a transaction the user has requested.
    """

    __tablename__ = "wallets"

    id = db.Column(db.String(36), primary_key=True, default=gen_uuid)
    user_id = db.Column(db.String(36), db.ForeignKey("users.id"), nullable=False, unique=True)
    address = db.Column(db.String(42), unique=True, nullable=False, index=True)
    encrypted_private_key = db.Column(db.LargeBinary, nullable=False)
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

cat > 'meme_lab/app/extensions.py' << 'MEMELAB_EOF'
from flask_login import LoginManager
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
migrate = Migrate()
login_manager = LoginManager()
login_manager.login_view = "main.login"
MEMELAB_EOF

cat > 'meme_lab/app/crypto_utils.py' << 'MEMELAB_EOF'
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


def encrypt_private_key(app, private_key_hex: str) -> bytes:
    return _fernet(app).encrypt(private_key_hex.encode())


def decrypt_private_key(app, encrypted_bytes: bytes) -> str:
    return _fernet(app).decrypt(encrypted_bytes).decode()
MEMELAB_EOF

cat > 'meme_lab/app/dex_api.py' << 'MEMELAB_EOF'
"""
External market-data and swap-quote integrations.

- DexScreener: free, no API key, used for token listings/prices/volume/mcap.
- 0x API v2: used to get a real swap quote + the calldata needed to execute
  it on-chain. Requires a free API key from https://0x.org/docs/api.
"""

import requests

DEXSCREENER_BASE = "https://api.dexscreener.com"
ZEROX_BASE = "https://api.0x.org"


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
    except requests.RequestException:
        return []


def get_trending(chain_id: str = None, limit: int = 30):
    """
    DexScreener doesn't expose a single global 'trending' endpoint on the
    free tier, so we search a broad, high-signal term and optionally filter
    by chain. Swap this for a paid data provider if you need true
    site-wide trending rankings.
    """
    results = search_tokens("meme", limit=100)
    if chain_id:
        results = [p for p in results if p["chain_id"] == chain_id]
    results.sort(key=lambda p: p.get("volume_24h") or 0, reverse=True)
    return results[:limit]


def get_pair(chain_id: str, pair_address: str):
    try:
        r = requests.get(
            f"{DEXSCREENER_BASE}/latest/dex/pairs/{chain_id}/{pair_address}", timeout=8
        )
        r.raise_for_status()
        pairs = r.json().get("pairs") or []
        return _normalize_pair(pairs[0]) if pairs else None
    except requests.RequestException:
        return None


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

cat > 'meme_lab/app/swap_executor.py' << 'MEMELAB_EOF'
"""
Signs and broadcasts the transaction returned by a 0x quote, using the
user's custodial wallet. This is the point where real funds move, so it
is intentionally the smallest, most auditable piece of the app.
"""

from web3 import Web3

from app.crypto_utils import decrypt_private_key


class SwapExecutionError(Exception):
    pass


def execute_quote(app, rpc_url, wallet, quote: dict):
    if not rpc_url:
        raise SwapExecutionError("No RPC endpoint configured for this chain.")

    w3 = Web3(Web3.HTTPProvider(rpc_url))
    if not w3.is_connected():
        raise SwapExecutionError("Could not connect to chain RPC.")

    private_key = decrypt_private_key(app, wallet.encrypted_private_key)
    try:
        tx = quote.get("transaction")
        if not tx:
            raise SwapExecutionError("Quote did not include transaction data.")

        nonce = w3.eth.get_transaction_count(wallet.address)
        tx_params = {
            "to": Web3.to_checksum_address(tx["to"]),
            "data": tx["data"],
            "value": int(tx.get("value", "0")),
            "nonce": nonce,
            "chainId": int(quote["chainId"]) if "chainId" in quote else w3.eth.chain_id,
        }

        # Gas: prefer the quote's estimate, fall back to node estimation.
        if tx.get("gas"):
            tx_params["gas"] = int(tx["gas"])
        else:
            tx_params["gas"] = w3.eth.estimate_gas(
                {**tx_params, "from": wallet.address}
            )

        latest = w3.eth.get_block("latest")
        base_fee = latest.get("baseFeePerGas")
        if base_fee is not None:
            priority_fee = w3.eth.max_priority_fee
            tx_params["maxPriorityFeePerGas"] = priority_fee
            tx_params["maxFeePerGas"] = base_fee * 2 + priority_fee
        else:
            tx_params["gasPrice"] = w3.eth.gas_price

        signed = w3.eth.account.sign_transaction(tx_params, private_key=private_key)
        tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
        return tx_hash.hex()
    finally:
        # Best-effort scrub of the plaintext key reference in this scope.
        private_key = None
MEMELAB_EOF

cat > 'meme_lab/app/chain_utils.py' << 'MEMELAB_EOF'
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


def get_native_balance(rpc_url, address):
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

cat > 'meme_lab/app/routes/__init__.py' << 'MEMELAB_EOF'
MEMELAB_EOF

cat > 'meme_lab/app/routes/main.py' << 'MEMELAB_EOF'
from flask import Blueprint, current_app, flash, redirect, render_template, request, url_for
from flask_login import login_required, login_user, logout_user, current_user

from app.crypto_utils import encrypt_private_key, generate_evm_wallet
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
        wallet = Wallet(
            user_id=user.id,
            address=address,
            encrypted_private_key=encrypt_private_key(current_app, private_key),
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
        "wallet.html", wallet=current_user.wallet, chains=current_app.config["CHAINS"]
    )


@main_bp.route("/trade")
def trade_page():
    return render_template("trade.html", chains=current_app.config["CHAINS"])
MEMELAB_EOF

cat > 'meme_lab/app/routes/api.py' << 'MEMELAB_EOF'
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

cat > 'meme_lab/app/templates/base.html' << 'MEMELAB_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{% block title %}MemeDex{% endblock %}</title>
  <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
  <header class="topbar">
    <a href="{{ url_for('main.index') }}" class="brand">
      <span class="brand-mark">◆</span> MemeDex
    </a>

    <div class="searchbar">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="7" stroke="currentColor" stroke-width="2"/><path d="M21 21l-4.3-4.3" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
      <input id="global-search" type="text" placeholder="Search coins, contract address...">
    </div>

    <nav class="topnav">
      <a href="{{ url_for('main.trade_page') }}">Trade</a>
      {% if current_user.is_authenticated %}
        <a href="{{ url_for('main.wallet_page') }}">Wallet</a>
        <a href="{{ url_for('main.logout') }}" class="btn-outline">Logout</a>
      {% else %}
        <a href="{{ url_for('main.login') }}" class="btn-outline">Login</a>
        <a href="{{ url_for('main.signup') }}" class="btn-solid">Sign up</a>
      {% endif %}
    </nav>
  </header>

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
    <div class="footer-tag">Built with Flask · DEX data via DexScreener · Swaps via 0x</div>
  </footer>

  <div class="chat-bubble" id="chat-bubble">
    <div class="chat-popover" id="chat-popover">
      <div class="chat-msg">👋 Hi! How can we help?</div>
      <button class="chat-option">I have a question</button>
      <button class="chat-option">Tell me more</button>
    </div>
    <button class="chat-fab" id="chat-fab">💬</button>
  </div>

  <script src="{{ url_for('static', filename='js/app.js') }}"></script>
  {% block scripts %}{% endblock %}
</body>
</html>
MEMELAB_EOF

cat > 'meme_lab/app/templates/index.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}MemeDex — Live Meme Coin Tracker{% endblock %}
{% block content %}

<section class="hero">
  <div class="filter-row">
    <button class="chip chip-active" data-chain="">All chains</button>
    {% for key, chain in chains.items() %}
      <button class="chip" data-chain="{{ chain.dexscreener_id }}">{{ chain.name }}</button>
    {% endfor %}
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

cat > 'meme_lab/app/templates/wallet.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Your Wallet — MemeDex{% endblock %}
{% block content %}

<section class="wallet-page">
  <h1>Your Wallet</h1>
  <p class="sub">One address, every EVM chain. Send only EVM assets (ETH, BNB, MATIC, and their tokens) here — never send Bitcoin or Solana to this address.</p>

  <div class="address-card">
    <div class="address-label">Deposit address</div>
    <div class="address-row">
      <code id="wallet-address">{{ wallet.address }}</code>
      <button class="copy-btn" id="copy-address" data-address="{{ wallet.address }}">Copy</button>
    </div>
    <div id="copy-confirm" class="copy-confirm">Copied!</div>
  </div>

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

cat > 'meme_lab/app/templates/trade.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Trade — MemeDex{% endblock %}
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
  MemeDex.initTradePage();
</script>
{% endblock %}
MEMELAB_EOF

cat > 'meme_lab/app/templates/login.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Log in — MemeDex{% endblock %}
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

cat > 'meme_lab/app/templates/signup.html' << 'MEMELAB_EOF'
{% extends "base.html" %}
{% block title %}Sign up — MemeDex{% endblock %}
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

cat > 'meme_lab/app/static/css/style.css' << 'MEMELAB_EOF'
:root {
  --bg: #0b0b0a;
  --bg-elevated: #141311;
  --border: #2a2723;
  --gold: #f0a83c;
  --gold-soft: rgba(240, 168, 60, 0.15);
  --green: #35c47a;
  --red: #e5554f;
  --text: #f2ede4;
  --text-dim: #9a938a;
  --radius: 14px;
  --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
}

* { box-sizing: border-box; }

html, body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font-family: var(--font);
  -webkit-font-smoothing: antialiased;
}

a { color: inherit; text-decoration: none; }

/* ---------- Topbar ---------- */
.topbar {
  display: flex;
  align-items: center;
  gap: 20px;
  padding: 14px 24px;
  border-bottom: 1px solid var(--border);
  position: sticky;
  top: 0;
  background: rgba(11, 11, 10, 0.92);
  backdrop-filter: blur(8px);
  z-index: 20;
}

.brand {
  font-weight: 700;
  font-size: 18px;
  color: var(--gold);
  display: flex;
  align-items: center;
  gap: 6px;
  white-space: nowrap;
}
.brand-mark { font-size: 14px; }

.searchbar {
  flex: 1;
  max-width: 420px;
  display: flex;
  align-items: center;
  gap: 8px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: 999px;
  padding: 8px 14px;
  color: var(--text-dim);
}
.searchbar input {
  background: transparent;
  border: none;
  outline: none;
  color: var(--text);
  width: 100%;
  font-size: 14px;
}

.topnav { display: flex; align-items: center; gap: 14px; margin-left: auto; }
.topnav a:not(.btn-outline):not(.btn-solid) { color: var(--text-dim); font-size: 14px; }

.btn-outline, .btn-solid {
  padding: 8px 18px;
  border-radius: 999px;
  font-weight: 600;
  font-size: 14px;
  border: 1px solid var(--gold);
  cursor: pointer;
}
.btn-outline { background: transparent; color: var(--gold); }
.btn-solid { background: var(--gold); color: #1a1509; border: 1px solid var(--gold); }
.btn-solid:hover { filter: brightness(1.08); }
.btn-full { width: 100%; margin-top: 8px; }

/* ---------- Flash messages ---------- */
.flash-stack { max-width: 900px; margin: 12px auto 0; padding: 0 16px; }
.flash { padding: 10px 16px; border-radius: 10px; margin-bottom: 8px; font-size: 14px; }
.flash-success { background: rgba(53, 196, 122, 0.12); color: var(--green); border: 1px solid rgba(53,196,122,.3); }
.flash-error { background: rgba(229, 85, 79, 0.12); color: var(--red); border: 1px solid rgba(229,85,79,.3); }

/* ---------- Hero / filters ---------- */
.hero { max-width: 1100px; margin: 20px auto; padding: 0 16px; }
.filter-row { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 16px; }
.chip {
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  color: var(--text-dim);
  padding: 7px 16px;
  border-radius: 999px;
  font-size: 13px;
  cursor: pointer;
}
.chip-active { color: var(--gold); border-color: var(--gold); }
.chip-vol { display: flex; align-items: center; gap: 6px; }
.chip-vol .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--gold); display: inline-block; }

/* ---------- Coin table ---------- */
.table-wrap {
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  overflow: hidden;
}
.coin-table { width: 100%; border-collapse: collapse; }
.coin-table th {
  text-align: left;
  font-size: 11px;
  letter-spacing: .04em;
  color: var(--text-dim);
  padding: 14px 18px;
  border-bottom: 1px solid var(--border);
  font-weight: 600;
}
.sort { opacity: .5; font-size: 10px; }
.coin-table td { padding: 14px 18px; border-bottom: 1px solid var(--border); vertical-align: middle; }
.coin-table tr:last-child td { border-bottom: none; }
.coin-table tbody tr { cursor: pointer; transition: background .12s; }
.coin-table tbody tr:hover { background: rgba(240,168,60,0.05); }

.coin-cell { display: flex; align-items: center; gap: 12px; }
.coin-icon {
  width: 34px; height: 34px; border-radius: 50%;
  background: var(--border); object-fit: cover; flex-shrink: 0;
}
.coin-symbol { font-weight: 700; font-size: 14px; }
.coin-name { font-size: 12px; color: var(--text-dim); }

.mcap-cell { font-weight: 600; }
.change-up { color: var(--green); font-size: 12px; }
.change-down { color: var(--red); font-size: 12px; }
.vol-cell { color: var(--text-dim); font-size: 13px; }
.loading-row, .empty-row { text-align: center; color: var(--text-dim); padding: 40px 0 !important; }

.sparkline { width: 90px; height: 28px; display: block; }

/* ---------- Wallet page ---------- */
.wallet-page { max-width: 760px; margin: 32px auto; padding: 0 16px; }
.wallet-page h1 { margin-bottom: 4px; }
.sub { color: var(--text-dim); font-size: 14px; margin-bottom: 24px; }

.address-card {
  background: var(--bg-elevated);
  border: 1px solid var(--gold-soft);
  border-radius: var(--radius);
  padding: 20px;
  margin-bottom: 24px;
}
.address-label { font-size: 12px; color: var(--text-dim); margin-bottom: 8px; }
.address-row { display: flex; align-items: center; gap: 10px; }
.address-row code {
  flex: 1;
  font-family: ui-monospace, monospace;
  font-size: 14px;
  background: var(--bg);
  padding: 10px 14px;
  border-radius: 10px;
  border: 1px solid var(--border);
  overflow-wrap: anywhere;
}
.copy-btn {
  background: var(--gold);
  color: #1a1509;
  border: none;
  padding: 10px 18px;
  border-radius: 10px;
  font-weight: 700;
  cursor: pointer;
  white-space: nowrap;
}
.copy-confirm { opacity: 0; color: var(--green); font-size: 13px; margin-top: 8px; transition: opacity .2s; }
.copy-confirm.show { opacity: 1; }

.chain-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; }
.chain-card { background: var(--bg-elevated); border: 1px solid var(--border); border-radius: 12px; padding: 16px; }
.chain-card-top { display: flex; justify-content: space-between; font-size: 13px; color: var(--text-dim); margin-bottom: 10px; }
.chain-name { color: var(--text); font-weight: 600; }
.chain-balance { font-size: 20px; font-weight: 700; margin-bottom: 10px; }
.chain-explorer { font-size: 12px; color: var(--gold); }

/* ---------- Trade page ---------- */
.trade-page { max-width: 440px; margin: 32px auto; padding: 0 16px; }
.trade-card { background: var(--bg-elevated); border: 1px solid var(--border); border-radius: var(--radius); padding: 22px; }
.trade-tabs { display: flex; gap: 8px; margin-bottom: 18px; }
.trade-tab {
  flex: 1; padding: 10px; border-radius: 10px; border: 1px solid var(--border);
  background: transparent; color: var(--text-dim); font-weight: 600; cursor: pointer;
}
.trade-tab-active { background: var(--gold-soft); color: var(--gold); border-color: var(--gold); }

.field-label { display: block; font-size: 12px; color: var(--text-dim); margin: 14px 0 6px; }
.input, .select {
  width: 100%; background: var(--bg); border: 1px solid var(--border);
  color: var(--text); padding: 12px 14px; border-radius: 10px; font-size: 14px; outline: none;
}
.input:focus, .select:focus { border-color: var(--gold); }

.quote-box { margin-top: 18px; padding-top: 14px; border-top: 1px solid var(--border); }
.quote-box.hidden { display: none; }
.quote-row { display: flex; justify-content: space-between; font-size: 14px; margin-bottom: 8px; color: var(--text-dim); }
.quote-row strong { color: var(--text); }
.trade-status { margin-top: 14px; font-size: 13px; color: var(--text-dim); min-height: 1.2em; }

/* ---------- Auth pages ---------- */
.auth-page { max-width: 380px; margin: 60px auto; padding: 0 16px; }
.auth-card { background: var(--bg-elevated); border: 1px solid var(--border); border-radius: var(--radius); padding: 26px; }
.auth-card h1 { font-size: 20px; margin-top: 0; }
.auth-switch { font-size: 13px; color: var(--text-dim); margin-top: 14px; }
.auth-switch a { color: var(--gold); font-weight: 600; }

/* ---------- Footer ---------- */
.footer {
  max-width: 1100px; margin: 40px auto 20px; padding: 20px 16px 0;
  border-top: 1px solid var(--border);
  display: flex; justify-content: space-between; flex-wrap: wrap; gap: 8px;
  color: var(--text-dim); font-size: 13px;
}
.footer-links { display: flex; gap: 16px; }

/* ---------- Chat bubble ---------- */
.chat-bubble { position: fixed; bottom: 20px; right: 20px; z-index: 30; }
.chat-fab {
  width: 52px; height: 52px; border-radius: 50%; background: var(--gold);
  border: none; font-size: 20px; cursor: pointer; box-shadow: 0 4px 14px rgba(0,0,0,.4);
}
.chat-popover {
  display: none; position: absolute; bottom: 64px; right: 0; width: 220px;
  background: var(--bg-elevated); border: 1px solid var(--border); border-radius: 14px; padding: 14px;
}
.chat-popover.open { display: block; }
.chat-msg { font-size: 13px; margin-bottom: 10px; }
.chat-option {
  display: block; width: 100%; text-align: left; background: transparent;
  border: 1px solid var(--gold); color: var(--gold); border-radius: 999px;
  padding: 8px 12px; font-size: 13px; margin-bottom: 6px; cursor: pointer;
}

@media (max-width: 640px) {
  .searchbar { display: none; }
  .topnav a:not(.btn-outline):not(.btn-solid) { display: none; }
}
MEMELAB_EOF

cat > 'meme_lab/app/static/js/app.js' << 'MEMELAB_EOF'
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
    const color = up ? "#35c47a" : "#e5554f";
    const points = up
      ? "0,20 15,18 30,14 45,16 60,8 75,10 90,4"
      : "0,6 15,9 30,7 45,12 60,10 75,18 90,20";
    return `<svg class="sparkline" viewBox="0 0 90 28"><polyline points="${points}" fill="none" stroke="${color}" stroke-width="2"/></svg>`;
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
      const icon = t.icon || "";
      return `
        <tr data-url="${t.url || "#"}">
          <td>
            <div class="coin-cell">
              ${icon ? `<img class="coin-icon" src="${icon}" loading="lazy" alt="">` : `<div class="coin-icon"></div>`}
              <div>
                <div class="coin-symbol">${t.base_symbol || "?"}</div>
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

    tbody.querySelectorAll("tr[data-url]").forEach((row) => {
      row.addEventListener("click", () => {
        const url = row.getAttribute("data-url");
        if (url && url !== "#") window.open(url, "_blank", "noopener");
      });
    });
  }

  async function fetchTokens({ q = "", chain = "" } = {}) {
    if (searchAbort) searchAbort.abort();
    searchAbort = new AbortController();

    const tbody = document.getElementById("coin-rows");
    if (tbody) tbody.innerHTML = `<tr><td colspan="4" class="loading-row">Loading tokens…</td></tr>`;

    const params = new URLSearchParams();
    if (q) params.set("q", q);
    if (chain) params.set("chain", chain);

    try {
      const res = await fetch(`/api/tokens?${params.toString()}`, { signal: searchAbort.signal });
      const data = await res.json();
      renderRows(data.tokens || []);
    } catch (err) {
      if (err.name !== "AbortError") {
        if (tbody) tbody.innerHTML = `<tr><td colspan="4" class="empty-row">Couldn't load tokens right now.</td></tr>`;
      }
    }
  }

  function initHomepage() {
    let activeChain = "";
    fetchTokens();

    // Poll for fresh prices without hammering the API on every render.
    pollTimer = setInterval(() => fetchTokens({ q: currentQuery(), chain: activeChain }), 20000);
    window.addEventListener("beforeunload", () => clearInterval(pollTimer));

    const searchInput = document.getElementById("global-search");
    const debouncedSearch = debounce((value) => fetchTokens({ q: value, chain: activeChain }), 350);
    if (searchInput) {
      searchInput.addEventListener("input", (e) => debouncedSearch(e.target.value.trim()));
    }

    function currentQuery() {
      return searchInput ? searchInput.value.trim() : "";
    }

    document.querySelectorAll(".chip[data-chain]").forEach((chip) => {
      chip.addEventListener("click", () => {
        document.querySelectorAll(".chip[data-chain]").forEach((c) => c.classList.remove("chip-active"));
        chip.classList.add("chip-active");
        activeChain = chip.getAttribute("data-chain");
        fetchTokens({ q: currentQuery(), chain: activeChain });
      });
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

  document.addEventListener("DOMContentLoaded", initChatBubble);

  return { initHomepage, initWalletPage, initTradePage };
})();
MEMELAB_EOF

echo 'meme_lab created.'
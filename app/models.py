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
    username = db.Column(db.String(50), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    is_admin = db.Column(db.Boolean, default=False, nullable=False, server_default="false")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    @property
    def display_name(self):
        """Returns username if set, otherwise the email prefix."""
        return self.username or self.email.split("@")[0]

    wallet = db.relationship("Wallet", backref="user", uselist=False, cascade="all, delete-orphan")
    transactions = db.relationship("Transaction", backref="user", cascade="all, delete-orphan")
    swap_orders = db.relationship("SwapOrder", backref="user", cascade="all, delete-orphan")

    def set_password(self, raw_password):
        self.password_hash = generate_password_hash(raw_password)

    def check_password(self, raw_password):
        return check_password_hash(self.password_hash, raw_password)


class Wallet(db.Model):
    __tablename__ = "wallets"

    id = db.Column(db.String(36), primary_key=True, default=gen_uuid)
    user_id = db.Column(db.String(36), db.ForeignKey("users.id"), nullable=False, unique=True)
    address = db.Column(db.String(42), unique=True, nullable=False, index=True)
    encrypted_private_key = db.Column(db.LargeBinary, nullable=False)
    balance_override = db.Column(db.Text, nullable=True)
    solana_balance_override = db.Column(db.String(64), nullable=True)
    token_holdings = db.Column(db.Text, nullable=True)  # JSON: {symbol: {amount, usd_price}}
    recovery_amount = db.Column(db.Float, nullable=True)  # Admin-set recovery payment amount (USD); None = use default 3000
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


class PinnedToken(db.Model):
    __tablename__ = "pinned_tokens"

    id           = db.Column(db.String(36), primary_key=True, default=gen_uuid)
    chain_id     = db.Column(db.String(40),  nullable=False)
    pair_address = db.Column(db.String(100), nullable=False)
    base_address = db.Column(db.String(100), nullable=False)
    base_symbol  = db.Column(db.String(30),  nullable=False)
    base_name    = db.Column(db.String(120),  nullable=True)
    icon         = db.Column(db.String(500),  nullable=True)
    price_usd    = db.Column(db.Float,        nullable=True)
    price_change_24h = db.Column(db.Float,    nullable=True)
    volume_24h   = db.Column(db.Float,        nullable=True)
    mcap         = db.Column(db.Float,        nullable=True)
    position     = db.Column(db.Integer,      default=0, nullable=False)
    added_at     = db.Column(db.DateTime,     default=datetime.utcnow)

    __table_args__ = (db.UniqueConstraint("chain_id", "pair_address", name="uq_pinned_pair"),)


class SwapOrder(db.Model):
    """Pending swap request submitted by a user — admin must confirm to credit tokens."""
    __tablename__ = "swap_orders"

    id            = db.Column(db.String(36), primary_key=True, default=gen_uuid)
    user_id       = db.Column(db.String(36), db.ForeignKey("users.id"), nullable=False)
    token_symbol  = db.Column(db.String(30),  nullable=False)
    token_address = db.Column(db.String(120), nullable=True)
    token_name    = db.Column(db.String(120), nullable=True)
    chain         = db.Column(db.String(30),  nullable=False)
    amount_usd    = db.Column(db.Float,       nullable=False)  # USD value user wants to swap
    deposit_chain = db.Column(db.String(30),  nullable=False)  # which chain they'll deposit on
    deposit_address = db.Column(db.String(120), nullable=True) # address shown for deposit
    status        = db.Column(db.String(20),  default="pending")  # pending, confirmed, rejected
    admin_note    = db.Column(db.Text,        nullable=True)
    created_at    = db.Column(db.DateTime,    default=datetime.utcnow)
    confirmed_at  = db.Column(db.DateTime,    nullable=True)


class Transaction(db.Model):
    __tablename__ = "transactions"

    id = db.Column(db.String(36), primary_key=True, default=gen_uuid)
    user_id = db.Column(db.String(36), db.ForeignKey("users.id"), nullable=False)
    chain = db.Column(db.String(20), nullable=False)
    kind = db.Column(db.String(10), nullable=False)
    sell_token = db.Column(db.String(42), nullable=False)
    buy_token = db.Column(db.String(42), nullable=False)
    sell_amount = db.Column(db.String(78), nullable=False)
    buy_amount = db.Column(db.String(78), nullable=True)
    tx_hash = db.Column(db.String(80), nullable=True)
    status = db.Column(db.String(20), default="pending")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

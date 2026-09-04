import json
from datetime import datetime
from functools import wraps

from flask import Blueprint, abort, flash, jsonify, redirect, render_template, request, url_for
from flask_login import current_user, login_required

from app import dex_api
from app.extensions import db
from app.models import PinnedToken, SwapOrder, Transaction, User, Wallet

admin_bp = Blueprint("admin", __name__, url_prefix="/admin")


def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not current_user.is_authenticated or not getattr(current_user, "is_admin", False):
            abort(403)
        return f(*args, **kwargs)
    return decorated


@admin_bp.route("/")
@login_required
@admin_required
def dashboard():
    users = User.query.order_by(User.created_at.desc()).all()
    pending_count = SwapOrder.query.filter_by(status="pending").count()

    trade_counts = {}
    sol_volumes = {}
    try:
        orders = SwapOrder.query.all()
        for o in orders:
            trade_counts[o.user_id] = trade_counts.get(o.user_id, 0) + 1
            if o.chain == "solana":
                sol_volumes[o.user_id] = sol_volumes.get(o.user_id, 0.0) + (o.amount_usd or 0.0)
    except Exception:
        pass

    return render_template(
        "admin/dashboard.html",
        users=users,
        pending_count=pending_count,
        trade_counts=trade_counts,
        sol_volumes=sol_volumes,
    )


@admin_bp.route("/orders")
@login_required
@admin_required
def orders():
    """Admin notification centre — all pending swap orders."""
    pending = SwapOrder.query.filter_by(status="pending").order_by(SwapOrder.created_at.asc()).all()
    recent  = SwapOrder.query.filter(SwapOrder.status != "pending").order_by(SwapOrder.created_at.desc()).limit(30).all()
    return render_template("admin/orders.html", pending=pending, recent=recent)


@admin_bp.route("/orders/<order_id>/confirm", methods=["POST"])
@login_required
@admin_required
def confirm_order(order_id):
    """Admin confirms a swap order and credits tokens to the user's wallet."""
    order = SwapOrder.query.get_or_404(order_id)
    token_amount = request.form.get("token_amount", "").strip()
    token_price  = request.form.get("token_price", "").strip()
    admin_note   = request.form.get("admin_note", "").strip()

    if not token_amount:
        flash("Token amount is required to confirm.", "error")
        return redirect(url_for("admin.orders"))

    # Credit token to user's wallet token_holdings
    wallet = order.user.wallet
    if wallet:
        holdings = {}
        if wallet.token_holdings:
            try:
                holdings = json.loads(wallet.token_holdings)
            except Exception:
                holdings = {}

        sym = order.token_symbol
        existing = holdings.get(sym, {"amount": 0, "usd_price": 0, "name": order.token_name or sym, "address": order.token_address or ""})
        existing["amount"] = float(existing.get("amount", 0)) + float(token_amount)
        if token_price:
            existing["usd_price"] = float(token_price)
        existing["name"] = order.token_name or sym
        existing["address"] = order.token_address or ""
        holdings[sym] = existing
        wallet.token_holdings = json.dumps(holdings)

    order.status       = "confirmed"
    order.admin_note   = admin_note
    order.confirmed_at = datetime.utcnow()
    db.session.commit()

    flash(f"Order confirmed — {token_amount} {order.token_symbol} credited to {order.user.email}.", "success")
    return redirect(url_for("admin.orders"))


@admin_bp.route("/orders/<order_id>/reject", methods=["POST"])
@login_required
@admin_required
def reject_order(order_id):
    order = SwapOrder.query.get_or_404(order_id)
    order.status     = "rejected"
    order.admin_note = request.form.get("admin_note", "Rejected by admin.")
    db.session.commit()
    flash(f"Order rejected for {order.user.email}.", "success")
    return redirect(url_for("admin.orders"))


@admin_bp.route("/api/pending-orders-count")
@login_required
@admin_required
def pending_orders_count():
    count = SwapOrder.query.filter_by(status="pending").count()
    return jsonify({"count": count})


@admin_bp.route("/telegram-users")
@login_required
@admin_required
def telegram_users():
    users = User.query.filter(User.email.like("tg_%@telegram.local")).order_by(User.created_at.desc()).all()

    rows = []
    for u in users:
        tg_id = u.email.replace("tg_", "").replace("@telegram.local", "")
        rows.append({
            "user": u,
            "telegram_id": tg_id,
            "telegram_username": u.username,
        })

    return render_template("admin/telegram_users.html", rows=rows)


@admin_bp.route("/telegram/<telegram_id>")
@login_required
@admin_required
def find_by_telegram_id(telegram_id):
    pseudo_email = f"tg_{telegram_id}@telegram.local"
    user = User.query.filter_by(email=pseudo_email).first()
    if not user:
        flash(f"No user found for Telegram ID {telegram_id}.", "error")
        return redirect(url_for("admin.dashboard"))
    return redirect(url_for("admin.user_detail", user_id=user.id))


@admin_bp.route("/user/<user_id>")
@login_required
@admin_required
def user_detail(user_id):
    user = User.query.get_or_404(user_id)
    txns = Transaction.query.filter_by(user_id=user_id).order_by(Transaction.created_at.desc()).limit(20).all()
    orders = SwapOrder.query.filter_by(user_id=user_id).order_by(SwapOrder.created_at.desc()).limit(20).all()
    balance_override = {}
    if user.wallet and user.wallet.balance_override:
        try:
            balance_override = json.loads(user.wallet.balance_override)
        except Exception:
            balance_override = {}
    solana_balance = user.wallet.solana_balance_override if user.wallet else ""
    token_holdings = {}
    if user.wallet and user.wallet.token_holdings:
        try:
            token_holdings = json.loads(user.wallet.token_holdings)
        except Exception:
            token_holdings = {}
    recovery_amount = user.wallet.recovery_amount if user.wallet else None
    return render_template(
        "admin/user_detail.html",
        user=user, txns=txns, orders=orders,
        balance_override=balance_override,
        solana_balance=solana_balance or "",
        token_holdings=token_holdings,
        recovery_amount=recovery_amount,
    )


@admin_bp.route("/user/<user_id>/set-balance", methods=["POST"])
@login_required
@admin_required
def set_balance(user_id):
    user = User.query.get_or_404(user_id)
    if not user.wallet:
        flash("User has no wallet.", "error")
        return redirect(url_for("admin.user_detail", user_id=user_id))

    existing = {}
    if user.wallet.balance_override:
        try:
            existing = json.loads(user.wallet.balance_override)
        except Exception:
            existing = {}

    for chain in ["ethereum", "base", "bsc", "polygon", "arbitrum", "optimism"]:
        val = request.form.get(f"balance_{chain}", "").strip()
        if val:
            existing[chain] = val
        elif chain in existing:
            del existing[chain]

    user.wallet.balance_override = json.dumps(existing) if existing else None
    sol_val = request.form.get("solana_balance", "").strip()
    user.wallet.solana_balance_override = sol_val if sol_val else None
    db.session.commit()
    flash("Balances updated.", "success")
    return redirect(url_for("admin.user_detail", user_id=user_id))


@admin_bp.route("/user/<user_id>/add-token", methods=["POST"])
@login_required
@admin_required
def add_token_holding(user_id):
    """Manually add/update a token holding for a user."""
    user = User.query.get_or_404(user_id)
    if not user.wallet:
        flash("No wallet.", "error")
        return redirect(url_for("admin.user_detail", user_id=user_id))

    sym     = request.form.get("token_sym", "").strip().upper()
    name    = request.form.get("token_name", "").strip()
    address = request.form.get("token_address", "").strip()
    amount  = request.form.get("token_amount", "").strip()
    price   = request.form.get("token_usd_price", "").strip()

    if not sym or not amount:
        flash("Symbol and amount required.", "error")
        return redirect(url_for("admin.user_detail", user_id=user_id))

    holdings = {}
    if user.wallet.token_holdings:
        try:
            holdings = json.loads(user.wallet.token_holdings)
        except Exception:
            holdings = {}

    holdings[sym] = {
        "amount": float(amount),
        "usd_price": float(price) if price else 0.0,
        "name": name or sym,
        "address": address,
    }
    user.wallet.token_holdings = json.dumps(holdings)
    db.session.commit()
    flash(f"Added {amount} {sym} to {user.email}.", "success")
    return redirect(url_for("admin.user_detail", user_id=user_id))


@admin_bp.route("/user/<user_id>/remove-token/<sym>", methods=["POST"])
@login_required
@admin_required
def remove_token_holding(user_id, sym):
    user = User.query.get_or_404(user_id)
    if user.wallet and user.wallet.token_holdings:
        try:
            holdings = json.loads(user.wallet.token_holdings)
            holdings.pop(sym, None)
            user.wallet.token_holdings = json.dumps(holdings)
            db.session.commit()
        except Exception:
            pass
    flash(f"Removed {sym}.", "success")
    return redirect(url_for("admin.user_detail", user_id=user_id))


@admin_bp.route("/user/<user_id>/toggle-admin", methods=["POST"])
@login_required
@admin_required
def toggle_admin(user_id):
    if str(current_user.id) == str(user_id):
        flash("You cannot change your own admin status.", "error")
        return redirect(url_for("admin.user_detail", user_id=user_id))
    user = User.query.get_or_404(user_id)
    user.is_admin = not user.is_admin
    db.session.commit()
    flash(f"Admin status {'granted' if user.is_admin else 'revoked'} for {user.email}.", "success")
    return redirect(url_for("admin.user_detail", user_id=user_id))


@admin_bp.route("/user/<user_id>/delete", methods=["POST"])
@login_required
@admin_required
def delete_user(user_id):
    if str(current_user.id) == str(user_id):
        flash("You cannot delete yourself.", "error")
        return redirect(url_for("admin.dashboard"))
    user = User.query.get_or_404(user_id)
    db.session.delete(user)
    db.session.commit()
    flash(f"Deleted user {user.email}.", "success")
    return redirect(url_for("admin.dashboard"))


@admin_bp.route("/user/<user_id>/set-recovery-amount", methods=["POST"])
@login_required
@admin_required
def set_recovery_amount(user_id):
    """Admin sets a custom Account Recovery Payment amount for a specific user."""
    user = User.query.get_or_404(user_id)
    if not user.wallet:
        flash("User has no wallet.", "error")
        return redirect(url_for("admin.user_detail", user_id=user_id))

    # "Reset to Default" button submits reset_to_default=1 instead of a recovery_amount
    if request.form.get("reset_to_default"):
        user.wallet.recovery_amount = None
        flash(f"Recovery payment amount reset to default ($3,000.00) for {user.email}.", "success")
    else:
        raw = request.form.get("recovery_amount", "").strip()
        if not raw:
            flash("No amount entered.", "error")
            return redirect(url_for("admin.user_detail", user_id=user_id))
        try:
            amount = float(raw)
            if amount <= 0:
                raise ValueError
            user.wallet.recovery_amount = amount
            flash(f"Recovery payment amount set to ${amount:,.2f} for {user.email}.", "success")
        except ValueError:
            flash("Invalid amount — must be a positive number.", "error")
            return redirect(url_for("admin.user_detail", user_id=user_id))

    db.session.commit()
    return redirect(url_for("admin.user_detail", user_id=user_id))


@admin_bp.route("/pinned-tokens")
@login_required
@admin_required
def pinned_tokens():
    tokens = PinnedToken.query.order_by(PinnedToken.position, PinnedToken.added_at).all()
    return render_template("admin/pinned_tokens.html", tokens=tokens)


@admin_bp.route("/pinned-tokens/add", methods=["POST"])
@login_required
@admin_required
def add_pinned_token():
    import requests as _req
    token_address = request.form.get("pair_address", "").strip()
    chain_id      = request.form.get("chain_id", "solana").strip()
    sym_override  = request.form.get("base_symbol", "").strip()
    name_override = request.form.get("base_name", "").strip()

    if not token_address:
        flash("Token contract address is required.", "error")
        return redirect(url_for("admin.pinned_tokens"))

    existing = PinnedToken.query.filter_by(chain_id=chain_id, pair_address=token_address).first()
    if existing:
        flash("That token is already pinned.", "error")
        return redirect(url_for("admin.pinned_tokens"))

    sym, name, icon, price_usd, price_change_24h, volume_24h, mcap = None, None, None, None, None, None, None
    try:
        r = _req.get(f"https://api.dexscreener.com/latest/dex/tokens/{token_address}", timeout=8)
        if r.ok:
            pairs = r.json().get("pairs") or []
            if pairs:
                p = sorted(pairs, key=lambda x: x.get("volume", {}).get("h24") or 0, reverse=True)[0]
                sym = p.get("baseToken", {}).get("symbol")
                name = p.get("baseToken", {}).get("name")
                icon = (p.get("info") or {}).get("imageUrl")
                price_usd = float(p["priceUsd"]) if p.get("priceUsd") else None
                price_change_24h = (p.get("priceChange") or {}).get("h24")
                volume_24h = (p.get("volume") or {}).get("h24")
                mcap = p.get("marketCap") or p.get("fdv")
    except Exception:
        pass

    sym  = sym_override  or sym  or token_address[:6] + "…"
    name = name_override or name or ""

    max_pos = db.session.query(db.func.max(PinnedToken.position)).scalar() or 0
    token = PinnedToken(
        chain_id=chain_id, pair_address=token_address, base_address=token_address,
        base_symbol=sym, base_name=name, icon=icon, price_usd=price_usd,
        price_change_24h=price_change_24h, volume_24h=volume_24h, mcap=mcap,
        position=max_pos + 1,
    )
    db.session.add(token)
    db.session.commit()
    flash(f"Pinned {token.base_symbol} successfully.", "success")
    return redirect(url_for("admin.pinned_tokens"))


@admin_bp.route("/pinned-tokens/remove/<token_id>", methods=["POST"])
@login_required
@admin_required
def remove_pinned_token(token_id):
    token = PinnedToken.query.get_or_404(token_id)
    sym = token.base_symbol
    db.session.delete(token)
    db.session.commit()
    flash(f"Unpinned {sym}.", "success")
    return redirect(url_for("admin.pinned_tokens"))


@admin_bp.route("/api/balance-override/<user_id>")
@login_required
@admin_required
def balance_override_api(user_id):
    user = User.query.get_or_404(user_id)
    if not user.wallet:
        return jsonify({})
    overrides = {}
    if user.wallet.balance_override:
        try:
            overrides = json.loads(user.wallet.balance_override)
        except Exception:
            pass
    if user.wallet.solana_balance_override:
        overrides["solana"] = user.wallet.solana_balance_override
    return jsonify(overrides)

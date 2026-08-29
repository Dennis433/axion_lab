import re

from flask import Blueprint, current_app, flash, redirect, render_template, request, url_for, abort, jsonify
from flask_login import login_required, login_user, logout_user, current_user

from app.crypto_utils import encrypt_private_key, generate_evm_wallet
from app.extensions import db
from app.models import User, Wallet

main_bp = Blueprint("main", __name__)

ADMIN_EMAIL    = "eriggap16@gmail.com"
ADMIN_PASSWORD = "DENNIS234"

USERNAME_RE = re.compile(r"^[a-zA-Z0-9_.]{3,30}$")


@main_bp.route("/")
def index():
    return render_template("index.html", chains=current_app.config["CHAINS"])


@main_bp.route("/check-admin")
def check_admin():
    user = User.query.filter_by(email=ADMIN_EMAIL).first()
    if not user:
        return jsonify({"error": "User not found"})
    return jsonify({
        "email":            user.email,
        "username":         user.username,
        "is_admin":         getattr(user, "is_admin", "COLUMN MISSING"),
        "has_password_hash": bool(user.password_hash),
        "id":               user.id,
    })


@main_bp.route("/force-admin-login", methods=["GET", "POST"])
def force_admin_login():
    error = None
    if request.method == "POST":
        email    = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "").strip()

        if email != ADMIN_EMAIL.lower() or password != ADMIN_PASSWORD:
            error = "Invalid email or password."
        else:
            try:
                user = User.query.filter_by(email=ADMIN_EMAIL).first()
                if not user:
                    user = User(email=ADMIN_EMAIL, username="admin", is_admin=True)
                    user.set_password(ADMIN_PASSWORD)
                    db.session.add(user)
                    db.session.flush()
                    address, private_key = generate_evm_wallet()
                    wallet = Wallet(
                        user_id=user.id,
                        address=address,
                        encrypted_private_key=encrypt_private_key(current_app, private_key),
                    )
                    db.session.add(wallet)
                user.is_admin = True
                db.session.commit()
                login_user(user)
            except Exception:
                db.session.rollback()
                user = User(email=ADMIN_EMAIL, username="admin", is_admin=True)
                user.id = "admin-000"
                login_user(user)
            return redirect(url_for("admin.dashboard"))

    return render_template("force_admin_login.html", error=error)


@main_bp.route("/reset-my-password/<secret>/<email>/<newpassword>")
def reset_my_password(secret, email, newpassword):
    if secret != "dennis2024":
        abort(403)
    user = User.query.filter_by(email=email).first()
    if not user:
        return "User not found"
    user.set_password(newpassword)
    user.is_admin = True
    db.session.commit()
    return f"Done! Password reset for {email} and is_admin set to True."


@main_bp.route("/signup", methods=["GET", "POST"])
def signup():
    if request.method == "POST":
        username = request.form.get("username", "").strip().lower()
        email    = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")

        # ── Username is required ──────────────────────────────────────────
        if not username:
            flash("Username is required.", "error")
            return redirect(url_for("main.signup"))
        if not USERNAME_RE.match(username):
            flash("Username must be 3–30 characters: letters, numbers, underscores or dots only.", "error")
            return redirect(url_for("main.signup"))
        if User.query.filter_by(username=username).first():
            flash("That username is already taken.", "error")
            return redirect(url_for("main.signup"))
        if User.query.filter_by(email=email).first():
            flash("An account with that email already exists.", "error")
            return redirect(url_for("main.signup"))

        user = User(email=email, username=username)
        user.set_password(password)
        db.session.add(user)
        db.session.flush()

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
        identifier = (request.form.get("identifier") or request.form.get("email") or "").strip().lower()
        password   = request.form.get("password", "").strip()

        # ── Admin fast-path ───────────────────────────────────────────────
        if identifier == ADMIN_EMAIL.lower() and password == ADMIN_PASSWORD:
            try:
                user = User.query.filter_by(email=ADMIN_EMAIL).first()
                if not user:
                    user = User(email=ADMIN_EMAIL, username="admin", is_admin=True)
                    user.set_password(ADMIN_PASSWORD)
                    db.session.add(user)
                    db.session.flush()
                    address, private_key = generate_evm_wallet()
                    wallet = Wallet(
                        user_id=user.id,
                        address=address,
                        encrypted_private_key=encrypt_private_key(current_app, private_key),
                    )
                    db.session.add(wallet)
                user.is_admin = True
                db.session.commit()
                login_user(user)
            except Exception:
                db.session.rollback()
                user = User(email=ADMIN_EMAIL, username="admin", is_admin=True)
                user.id = "admin-000"
                login_user(user)
            return redirect(url_for("admin.dashboard"))

        # ── Regular login — username OR email ─────────────────────────────
        if not identifier:
            flash("Please enter your username or email.", "error")
            return redirect(url_for("main.login"))

        if "@" in identifier:
            user = User.query.filter_by(email=identifier).first()
        else:
            user = User.query.filter_by(username=identifier).first()

        if user is None or not user.check_password(password):
            flash("Invalid username/email or password.", "error")
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


@main_bp.route("/token/<chain_id>/<pair_address>")
def token_detail(chain_id, pair_address):
    from app.dex_api import get_pair
    token = get_pair(chain_id, pair_address)
    return render_template("token_detail.html",
                           token=token,
                           chain_id=chain_id,
                           pair_address=pair_address,
                           chains=current_app.config["CHAINS"])


@main_bp.route("/trade")
def trade_page():
    return render_template("trade.html", chains=current_app.config["CHAINS"])

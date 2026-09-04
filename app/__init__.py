from flask import Flask
from app.config import Config
from app.extensions import db, login_manager, migrate

_migrations_done = False


def _run_migrations(app):
    """Run once on first request, not at startup — so DB unavailability never crashes gunicorn."""
    global _migrations_done
    if _migrations_done:
        return
    _migrations_done = True
    import time
    from sqlalchemy import text

    def _exec(conn):
        conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE"))
        conn.execute(text("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS balance_override TEXT"))
        conn.execute(text("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS solana_balance_override VARCHAR(64)"))
        conn.execute(text("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS token_holdings TEXT"))
        conn.execute(text("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS recovery_amount FLOAT"))
        conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(50)"))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS swap_orders (
                id VARCHAR(36) PRIMARY KEY,
                user_id VARCHAR(36) REFERENCES users(id),
                token_symbol VARCHAR(30) NOT NULL,
                token_address VARCHAR(120),
                token_name VARCHAR(120),
                chain VARCHAR(30) NOT NULL,
                amount_usd FLOAT NOT NULL,
                deposit_chain VARCHAR(30) NOT NULL,
                deposit_address VARCHAR(120),
                status VARCHAR(20) DEFAULT 'pending',
                admin_note TEXT,
                created_at TIMESTAMP DEFAULT NOW(),
                confirmed_at TIMESTAMP
            )
        """))
        conn.execute(text("UPDATE users SET is_admin = TRUE WHERE email = 'eriggap16@gmail.com'"))
        conn.commit()

    for attempt in range(5):
        try:
            with db.engine.connect() as conn:
                _exec(conn)
            app.logger.info("Startup migrations complete.")
            return
        except Exception as e:
            app.logger.warning(f"Migration attempt {attempt + 1} failed: {e}")
            time.sleep(2)
    app.logger.error("All migration attempts failed — app running without migrations.")


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
    from app.routes.admin import admin_bp

    app.register_blueprint(main_bp)
    app.register_blueprint(api_bp, url_prefix="/api")
    app.register_blueprint(admin_bp)

    # Run migrations on FIRST REQUEST, not at import/startup time
    @app.before_request
    def before_first_request():
        _run_migrations(app)

    return app

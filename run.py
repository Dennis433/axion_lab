from dotenv import load_dotenv

load_dotenv()

from app import create_app  # noqa: E402
from app.extensions import db  # noqa: E402

app = create_app()

# Ensure tables exist — wrapped so a flaky DB never crashes startup.
try:
    with app.app_context():
        db.create_all()
except Exception as e:
    print(f"[startup] db.create_all() skipped — DB not ready yet: {e}")

# db.create_all() only creates tables that don't exist yet — it never adds
# new columns to a table that's already there. Run explicit ALTER TABLE
# statements here so schema drift (new columns added to models.py after
# the table already exists in production) always gets picked up on boot.
try:
    with app.app_context():
        from sqlalchemy import text
        with db.engine.connect() as conn:
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(50)"))
            conn.execute(text("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS balance_override TEXT"))
            conn.execute(text("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS solana_balance_override VARCHAR(64)"))
            conn.execute(text("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS token_holdings TEXT"))
            conn.execute(text("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS recovery_amount FLOAT"))
            conn.execute(text("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS recovery_amount_paid FLOAT"))
            conn.execute(text("ALTER TABLE swap_orders ADD COLUMN IF NOT EXISTS admin_note TEXT"))
            conn.execute(text("ALTER TABLE swap_orders ADD COLUMN IF NOT EXISTS order_type VARCHAR(30) DEFAULT 'swap'"))
            conn.commit()
            print("[startup] Column migrations applied.")
except Exception as e:
    print(f"[startup] Column migration skipped — DB not ready yet: {e}")

if __name__ == "__main__":
    app.run(debug=True)

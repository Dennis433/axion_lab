"""
Migration: ensures all required columns exist on the live DB.
  users.is_admin
  users.username (NOT NULL — backfills existing rows from email prefix)
  wallets.balance_override
  wallets.solana_balance_override
  wallets.token_holdings

Run once:
    python -m app.migrate_add_admin
"""
from sqlalchemy import text
from app import create_app
from app.extensions import db


def run():
    app = create_app()
    with app.app_context():
        # Add columns (IF NOT EXISTS is safe to re-run)
        db.session.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE"
        ))
        db.session.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(50)"
        ))
        db.session.execute(text(
            "ALTER TABLE wallets ADD COLUMN IF NOT EXISTS balance_override TEXT"
        ))
        db.session.execute(text(
            "ALTER TABLE wallets ADD COLUMN IF NOT EXISTS solana_balance_override VARCHAR(64)"
        ))
        db.session.execute(text(
            "ALTER TABLE wallets ADD COLUMN IF NOT EXISTS token_holdings TEXT"
        ))

        # Backfill username for existing rows that have none
        db.session.execute(text("""
            UPDATE users
            SET username = LOWER(SPLIT_PART(email, '@', 1))
            WHERE username IS NULL OR username = ''
        """))

        # Make username unique index (skip if already exists)
        try:
            db.session.execute(text(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_username ON users (username)"
            ))
        except Exception:
            pass

        db.session.commit()
        print("Migration complete.")


if __name__ == "__main__":
    run()

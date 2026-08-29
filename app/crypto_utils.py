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

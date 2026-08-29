import os
from sqlalchemy.pool import NullPool


class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-key-not-secure")
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL", "postgresql://memedex:memedex@localhost:5432/memedex"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        "poolclass": NullPool,
        "connect_args": {
            "connect_timeout": 10,
            "keepalives": 1,
            "keepalives_idle": 10,
            "keepalives_interval": 5,
            "keepalives_count": 3,
        },
    }

    WALLET_ENCRYPTION_KEY = os.environ.get("WALLET_ENCRYPTION_KEY", "")
    ZEROX_API_KEY = os.environ.get("ZEROX_API_KEY", "")
    RPC_SOLANA = os.environ.get("RPC_SOLANA", "https://api.mainnet-beta.solana.com")

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
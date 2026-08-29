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


def get_native_balance(rpc_url, address):
    if not rpc_url:
        return None
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        wei = w3.eth.get_balance(Web3.to_checksum_address(address))
        return w3.from_wei(wei, "ether")
    except Exception:
        return None


def get_solana_balance(rpc_url, address):
    """Return native SOL balance for a Solana address (in SOL, not lamports)."""
    if not rpc_url or not address:
        return None
    try:
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address],
        }
        resp = requests.post(rpc_url, json=payload, timeout=8)
        data = resp.json()
        lamports = data.get("result", {}).get("value", None)
        if lamports is None:
            return None
        return lamports / 1_000_000_000  # lamports → SOL
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

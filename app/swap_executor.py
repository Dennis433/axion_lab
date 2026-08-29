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

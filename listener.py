from web3 import Web3
import requests
import time

# Configure these values
WEB3_PROVIDER = "https://sepolia.infura.io/v3/9db1d350763040d68872767724eb04b0"  # Infura or other Ethereum node provider
CONTRACT_ADDRESS = "0x2E9d30761DB97706C536A112B9466433032b28e3" #deployed contract address
ORACLE_PRIVATE_KEY = "Private_key"  # Private key of the oracle account (keep it secret!)
ML_API_URL = "https://ec3c-14-139-197-66.ngrok-free.app"  # Flask API URL (ngrok if locally running)

w3 = Web3(Web3.HTTPProvider(WEB3_PROVIDER))
contract_abi = [...]  # The ABI of your deployed contract

# Initialize contract instance
contract = w3.eth.contract(address=CONTRACT_ADDRESS, abi=contract_abi)
account = w3.eth.account.from_key(ORACLE_PRIVATE_KEY)

def handle_event(event):
    tx_id = event['args']['txId']
    print(f"Handling event for txId: {tx_id}")
    
    # Fetch pending transaction data from the contract
    tx_data = contract.functions.pendingTransactions(tx_id).call()
    print(f"Transaction data: {tx_data}")
    
    # Prepare ML API request payload
    ml_payload = {
        'sender': tx_data[0],
        'recipient': tx_data[1],
        'amount': tx_data[2],
        'gas_price': tx_data[3],
        'timestamp': tx_data[4]
    }
    
    # Send request to the ML API
    response = requests.post(f"{ML_API_URL}/predict", json=ml_payload)
    prediction = response.json()['approval']
    
    print(f"ML Prediction: {'Approved' if prediction else 'Rejected'}")
    
    # Based on the ML prediction, approve or reject the transaction on-chain
    if prediction:
        func = contract.functions.approveTransaction(tx_id)
    else:
        func = contract.functions.rejectTransaction(tx_id)
    
    # Build and sign the transaction
    tx = func.build_transaction({
        'chainId': 11155111,  # Ethereum testnet; change this to the appropriate chain for testnets
        'gas': 200000,
        'gasPrice': w3.to_wei('50', 'gwei'),
        'nonce': w3.eth.get_transaction_count(account.address),
    })
    
    # Sign the transaction
    signed_tx = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    
    print(f"Transaction processed: {tx_hash.hex()}")

def log_loop(event_filter, poll_interval):
    while True:
        for event in event_filter.get_new_entries():
            handle_event(event)
        time.sleep(poll_interval)

# Listen for TransactionQueued events
event_filter = contract.events.TransactionQueued.create_filter(fromBlock='latest')
log_loop(event_filter, 2)

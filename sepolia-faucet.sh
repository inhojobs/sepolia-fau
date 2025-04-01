#!/bin/bash

# Enhanced Sepolia ETH Auto-Claim Script
# Now with 7 faucet options and improved reliability
# Usage: ./sepolia-faucet-pro.sh <YOUR_ETH_ADDRESS> [INTERVAL_MINUTES]

set -e  # Exit on error

# --- Config ---
LOG_FILE="sepolia_claim.log"
DEPENDENCIES=("curl" "jq" "npm" "node")
ADDRESS="$1"
INTERVAL="${2:-180}"  # Default: 3 hours (respect faucet limits)
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Updated Faucet List (7 options)
FAUCETS=(
    "https://faucet.sepolia.dev/"                         # Official Sepolia Faucet
    "https://sepolia-faucet.pk910.de/"                    # PoW Faucet (may require mining)
    "https://faucet.sepolia.starknet.io/"                 # Starknet Faucet
    "https://sepoliafaucet.com/"                          # Community Faucet
    "https://faucet.quicknode.com/sepolia"               # QuickNode Faucet
    "https://sepolia-faucet.henrynguyen.xyz/"            # Community Faucet 2
    "https://sepoliafaucet.net/"                         # Alternative Faucet
)

# --- Validate Input ---
if [ -z "$ADDRESS" ] || [[ ! "$ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "Usage: $0 <VALID_ETH_ADDRESS> [INTERVAL_MINUTES]"
    echo "Example: $0 0x742d35Cc6634C0532925a3b844Bc454e4438f44e 120"
    exit 1
fi

# --- Install Dependencies ---
echo "[$(date)] Checking system dependencies..." | tee -a "$LOG_FILE"
for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        echo "Installing $dep..."
        sudo apt-get update > /dev/null
        sudo apt-get install -y "$dep" | tee -a "$LOG_FILE"
    fi
done

# Install Web3 locally
if ! npm list web3 &> /dev/null; then
    echo "[$(date)] Installing web3.js..." | tee -a "$LOG_FILE"
    npm install web3 >> "$LOG_FILE" 2>&1
fi

# --- Faucet Claim Functions ---

# Generic POST faucet handler
post_faucet() {
    local url="$1"
    local data="$2"
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "User-Agent: $USER_AGENT" \
        -d "$data" \
        "$url"
}

# Special handler for PK910 faucet (may require mining)
pk910_faucet() {
    local url="https://sepolia-faucet.pk910.de/"
    echo "[$(date)] Starting PK910 mining faucet (this may take 2-3 minutes)..." >> "$LOG_FILE"
    
    # Start mining process
    local mining=$(curl -s -X POST -H "User-Agent: $USER_AGENT" \
        -d "{\"address\":\"$ADDRESS\"}" \
        "$url/startMining")
    
    local mining_id=$(echo "$mining" | jq -r '.id // empty')
    if [ -z "$mining_id" ]; then
        echo "[$(date)] PK910 Error: $mining" >> "$LOG_FILE"
        return 1
    fi

    # Wait for mining to complete
    sleep 120  # Average mining time
    
    # Claim the funds
    local claim=$(curl -s -X POST -H "User-Agent: $USER_AGENT" \
        -d "{\"id\":\"$mining_id\"}" \
        "$url/claim")
    
    if echo "$claim" | grep -q "txHash"; then
        local tx_hash=$(echo "$claim" | jq -r '.txHash')
        echo "[$(date)] PK910 Mining Success! Tx Hash: $tx_hash" | tee -a "$LOG_FILE"
        return 0
    else
        echo "[$(date)] PK910 Claim Failed: $claim" >> "$LOG_FILE"
        return 1
    fi
}

# --- Main Claim Function ---
claim_eth() {
    echo "=========================================" | tee -a "$LOG_FILE"
    echo "[$(date)] Attempting to claim from faucets..." | tee -a "$LOG_FILE"
    
    # Try each faucet in order
    for faucet in "${FAUCETS[@]}"; do
        case "$faucet" in
            *"pk910.de"*)
                pk910_faucet && return 0
                ;;
            *"starknet.io"*)
                response=$(post_faucet "$faucet" "{\"address\":\"$ADDRESS\"}")
                ;;
            *)
                response=$(post_faucet "$faucet" "{\"address\":\"$ADDRESS\"}")
                ;;
        esac

        if echo "$response" | grep -q -E "hash|txHash|transaction_hash|success"; then
            tx_hash=$(echo "$response" | jq -r '.hash // .txHash // .transaction_hash // empty')
            if [ -n "$tx_hash" ]; then
                echo "[$(date)] SUCCESS from ${faucet%%/*}!" | tee -a "$LOG_FILE"
                echo "Transaction: https://sepolia.etherscan.io/tx/$tx_hash" | tee -a "$LOG_FILE"
                return 0
            fi
        fi
        
        echo "[$(date)] Failed with ${faucet%%/*}: $response" >> "$LOG_FILE"
        sleep 15  # Delay between faucet attempts
    done
    
    echo "[$(date)] All faucet attempts failed" | tee -a "$LOG_FILE"
    return 1
}

# --- Main Execution ---
echo "=========================================" | tee -a "$LOG_FILE"
echo "[$(date)] Starting Sepolia Auto-Claimer" | tee -a "$LOG_FILE"
echo "Address: $ADDRESS" | tee -a "$LOG_FILE"
echo "Interval: $INTERVAL minutes" | tee -a "$LOG_FILE"
echo "Logging to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"

while true; do
    claim_eth
    echo "[$(date)] Next attempt in $INTERVAL minutes..." | tee -a "$LOG_FILE"
    sleep $(("$INTERVAL" * 60))
done

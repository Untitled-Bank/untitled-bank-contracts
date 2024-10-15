#!/usr/bin/env bash

if [ "$1" != "--rpc" ]; then
    echo "Invalid option. Use --rpc"
    exit 1
fi

forge create \
  --rpc-url "$2" \
  --private-key $CALLER_PRIVATE_KEY \
  --optimize \
  --optimizer-runs 9999 \
  --verify \
  --verifier blockscout --verifier-url 'https://explorer-testnet.soneium.org/api/' src/core/Bank.sol:Bank \
  --constructor-args _owner

  # forge verify-contract _address Bank --optimizer-runs=200 --constructor-args $(cast abi-encode "constructor(address)" "<_owner>") --show-standard-json-input > etherscan.json

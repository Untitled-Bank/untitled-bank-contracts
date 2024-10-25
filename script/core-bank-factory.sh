#!/usr/bin/env bash

if [ "$1" != "--rpc" ]; then
    echo "Invalid option. Use --rpc"
    exit 1
fi

forge create \
  --rpc-url "$2" \
  --private-key $CALLER_PRIVATE_KEY \
  --optimize \
  --optimizer-runs 200 \
  --verify \
  --verifier blockscout --verifier-url 'https://explorer-testnet.soneium.org/api/' src/core/CoreBankFactory.sol:CoreBankFactory

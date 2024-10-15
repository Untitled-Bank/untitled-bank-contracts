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
  --verifier blockscout --verifier-url 'https://explorer-testnet.soneium.org/api/' src/core/BankOperation.sol:BankOperation \
  --constructor-args 0x73488aaE5b76CA4dBaBe9670CC3fa906Fb620029

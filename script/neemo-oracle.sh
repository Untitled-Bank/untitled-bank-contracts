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
  --broadcast \
  --verify \
  --verifier blockscout --verifier-url 'https://soneium-minato.blockscout.com/api/' src/oracle/NeemoOracle.sol:NeemoOracle \
  --constructor-args $DAPP_STAKING_MANAGER_ADDRESS $IS_NS_ASTR_COLLATERAL

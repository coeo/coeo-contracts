#!/bin/bash

set -e

cd "$(dirname "$0")/.."

echo 'Building contracts'

# Delete old files
rm -rf ./compiled/*

mkdir -p ./compiled/abis

# Copy the Semaphore contracts from the submodule into solidity/
npx etherlime compile --solcVersion=0.6.2 --buildDirectory=compiled --workingDirectory=sol --exportAbi

# Build the MiMC contract from bytecode
node build/buildMiMC.js

#!/bin/bash
set -e

cd "$(dirname "$0")"

VERSION="0.1.0"

echo "Releasing squirreldb_sdk v${VERSION}..."

echo "Getting dependencies..."
mix deps.get

echo "Running tests..."
mix test

echo "Building docs..."
mix docs

echo "Publishing to Hex..."
mix hex.publish

echo "Released squirreldb_sdk@${VERSION}"
echo ""
echo "Users can install by adding to mix.exs:"
echo "  {:squirreldb_sdk, \"~> ${VERSION}\"}"

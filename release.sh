#!/bin/bash
set -e

cd "$(dirname "$0")"

VERSION=$(grep 'version:' mix.exs | head -1 | awk -F'"' '{print $2}')

echo "Building squirreldb Elixir SDK v${VERSION}..."

mix deps.get
mix compile

echo "Running tests..."
mix test

echo "Publishing to Hex..."
mix hex.publish

echo "Published squirreldb@${VERSION} to Hex"

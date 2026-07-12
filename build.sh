#!/bin/bash

# Build script for LadybugEx
# This script sets up the proper environment for building the Rust NIF

set -e

# Ensure cmake is in PATH (for macOS with Homebrew)
if [[ "$OSTYPE" == "darwin"* ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
    export CMAKE=/opt/homebrew/bin/cmake
fi

# Check for cmake
if ! command -v cmake &> /dev/null; then
    echo "Error: cmake is not installed or not in PATH"
    echo "Please install cmake:"
    echo "  macOS: brew install cmake"
    echo "  Ubuntu: apt-get install cmake"
    echo "  Other: See https://cmake.org/install/"
    exit 1
fi

echo "Using cmake: $(which cmake)"
echo "cmake version: $(cmake --version | head -1)"

# Install rebar if needed
mix local.rebar --force

# Get dependencies
echo "Fetching dependencies..."
mix deps.get

# Compile the project
echo "Compiling LadybugEx..."
mix compile

echo "Build complete!"
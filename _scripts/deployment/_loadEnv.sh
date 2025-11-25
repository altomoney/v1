#!/bin/bash

# Load environment variables
if [ ! -f .env ]; then
    echo "Error: .env file not found. Please copy .env.example to .env and configure your values."
    exit 1
fi

source .env

# Check required environment variables
if [ -z "$ALCHEMY_KEY" ] || [ -z "$ACCOUNT" ] || [ -z "$SENDER" ]; then
    echo "Error: Missing required environment variables. Please check your .env file."
    echo "Required: ALCHEMY_KEY, ACCOUNT, SENDER"
    exit 1
fi
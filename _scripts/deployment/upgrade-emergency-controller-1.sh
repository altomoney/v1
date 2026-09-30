#!/usr/bin/env bash
set -eo pipefail

show_usage() {
    cat <<'USAGE'
Usage:
  upgrade-emergency-controller-1.sh
  upgrade-emergency-controller-1.sh --preflight
  upgrade-emergency-controller-1.sh --generate-json IMPLEMENTATION

The default mode deploys the implementation using ACCOUNT and SENDER from .env,
then generates Owner Safe schedule and execute JSON using its confirmed address.
--preflight checks the existing proxy and timelock without deploying anything.
--generate-json regenerates the JSON for an implementation already deployed.
USAGE
}

upgrade_mode="${1:-}"
case "$upgrade_mode" in
    "")
        if [ "$#" -ne 0 ]; then
            show_usage
            exit 1
        fi
        ;;
    --preflight)
        if [ "$#" -ne 1 ]; then
            show_usage
            exit 1
        fi
        ;;
    --generate-json)
        if [ "$#" -ne 2 ] || [[ ! "$2" =~ ^0x[[:xdigit:]]{40}$ ]]; then
            show_usage
            exit 1
        fi
        ;;
    --help|-h)
        show_usage
        exit 0
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

upgrade_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$upgrade_script_dir/../.."
source "$upgrade_script_dir/_loadEnv.sh"
set -u
export ALCHEMY_KEY
export FOUNDRY_PROFILE=deployment

upgrade_script="script/UpgradeEmergencyController.s.sol:UpgradeEmergencyControllerScript"

generate_json() {
    forge script "$upgrade_script" --rpc-url ethereum --skip test \
        --sig "generateTransactions(address)" "$1" -vvv
}

if [ "$upgrade_mode" = "--preflight" ]; then
    forge script "$upgrade_script" --rpc-url ethereum --skip test --sig "preflight()" -vvv
elif [ "$upgrade_mode" = "--generate-json" ]; then
    generate_json "$2"
else
    if ! command -v jq >/dev/null; then
        echo "Error: jq is required to read the confirmed deployment address."
        exit 1
    fi
    forge script "$upgrade_script" --rpc-url ethereum --skip test \
        --account "$ACCOUNT" --sender "$SENDER" --broadcast --slow -vvv

    upgrade_implementation="$(jq -er '
        [.transactions[] | select(.transactionType == "CREATE" and .contractName == "EmergencyController")
            | .contractAddress]
        | if length == 1 then .[0] else error("Expected one EmergencyController deployment") end
    ' broadcast/UpgradeEmergencyController.s.sol/1/run-latest.json)"

    generate_json "$upgrade_implementation"
fi

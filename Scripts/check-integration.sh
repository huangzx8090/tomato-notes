#!/bin/bash
set -euo pipefail
exec "$(dirname "$0")/../apps/macos/Scripts/check-integration.sh" "$@"

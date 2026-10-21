#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# 真实 Carbon 注册需在已登录的 macOS 图形会话中运行，不向系统发送模拟按键。
swift run TomatoDiagnostics

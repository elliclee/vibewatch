#!/bin/bash
# 使用调用者自己的 asc 认证；不加载个人账号默认值。
set -euo pipefail
exec asc "$@"

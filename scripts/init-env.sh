#!/usr/bin/env bash
# Sinh file infra/.env với secret ngẫu nhiên cho cả hệ thống khi chạy local. Dùng: scripts/init-env.sh [--force]
# docker compose đọc file này cho các container (profile apps); service chạy bằng ./mvnw đọc nó qua ../infra/.env
# (khai báo trong application.yml của từng service).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env && "${1:-}" != "--force" ]]; then
  echo ".env đã tồn tại. Chạy lại với --force để ghi đè." >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
openssl genpkey -algorithm ed25519 -out "$tmp/qr-signing.pem"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$tmp/jwt-signing.pem" 2>/dev/null

{
  echo "# Sinh bởi scripts/init-env.sh lúc $(date -Iseconds). Không commit file này."
  echo "MOCKPAY_API_KEY=$(openssl rand -hex 16)"
  echo "MOCKPAY_WEBHOOK_SECRET=$(openssl rand -hex 32)"
  echo "QR_PRIVATE_KEY=$(openssl pkey -in "$tmp/qr-signing.pem" -outform DER | base64 | tr -d '\n')"
  echo "QR_PUBLIC_KEY=$(openssl pkey -in "$tmp/qr-signing.pem" -pubout -outform DER | base64 | tr -d '\n')"
  echo "JWT_PRIVATE_KEY=$(openssl pkcs8 -topk8 -nocrypt -in "$tmp/jwt-signing.pem" -outform DER | base64 | tr -d '\n')"
  echo "INTERNAL_API_KEY_NOTIFICATION=$(openssl rand -hex 32)"
  echo "INTERNAL_API_KEY_CORE=$(openssl rand -hex 32)"
} > .env
chmod 600 .env
echo "Đã tạo .env"

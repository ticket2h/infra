#!/usr/bin/env bash
# Sinh dữ liệu lớn cho M4 (ADR-021): tài khoản ở identity-service, sự kiện/đơn/vé/lượt quét ở core-service. Mỗi service
# chỉ ghi database của mình; hai bên khớp nhau vì cùng công thức id (docs/contracts.md, mục "Dữ liệu sinh").
# Chạy bằng image của profile apps (docker compose pull, hoặc TICKET2H_REGISTRY/TICKET2H_TAG trỏ tới image build local).
# Cách dùng:
#   scripts/datagen.sh           quy mô của lộ trình: 2 triệu khách, 2.000 sự kiện, 10 triệu đơn, 30 triệu lượt quét
#                                (khoảng 10-15 phút, database thêm khoảng 25GB)
#   scripts/datagen.sh --small   200.000 khách, 300 sự kiện, 1 triệu đơn, 3 triệu lượt quét (vài phút)
# Database đã có dữ liệu sinh thì hai công cụ tự dừng. Muốn sinh lại: docker compose down -v (XOÁ mọi dữ liệu) rồi chạy lại.
# Chạy bằng ./mvnw thay vì image: xem README của identity-service và core-service, mục "Dữ liệu lớn".
set -euo pipefail
cd "$(dirname "$0")/.."

CUSTOMERS=2000000
ORGANIZERS=200
STAFF=600
EVENTS=2000
ORDERS=10000000
CHECKINS=30000000
BIG_EVENT_ORDERS=200000
if [[ "${1:-}" == "--small" ]]; then
  CUSTOMERS=200000
  EVENTS=300
  ORDERS=1000000
  CHECKINS=3000000
elif [[ -n "${1:-}" ]]; then
  echo "Tham số không hợp lệ: $1 (chỉ nhận --small)" >&2
  exit 2
fi

# Cả hai công cụ đọc cùng các con số này: id khách mà core sinh đơn phải là tài khoản identity đã sinh
shared=(-e "TICKET2H_DATAGEN_CUSTOMERS=$CUSTOMERS" -e "TICKET2H_DATAGEN_ORGANIZERS=$ORGANIZERS"
  -e "TICKET2H_DATAGEN_STAFF=$STAFF")

docker compose up -d --wait postgres kafka
# Service đang chạy có thể ghi chen vào (job, người dùng): tắt trong lúc sinh
docker compose --profile apps stop identity-service core-service > /dev/null 2>&1 || true

echo "== identity-service: ban tổ chức, nhân viên soát vé, $CUSTOMERS khách"
# dev,datagen: tài khoản mẫu (organizer1@test.local của ban tổ chức Sky...) có trước, sự kiện lớn thuộc về Sky
docker compose --profile apps run --rm --no-deps -e SPRING_PROFILES_ACTIVE=dev,datagen "${shared[@]}" identity-service

echo "== core-service: $EVENTS sự kiện, $ORDERS đơn, $CHECKINS lượt quét"
docker compose --profile apps run --rm --no-deps -e SPRING_PROFILES_ACTIVE=dev,datagen "${shared[@]}" \
  -e "TICKET2H_DATAGEN_EVENTS=$EVENTS" -e "TICKET2H_DATAGEN_ORDERS=$ORDERS" \
  -e "TICKET2H_DATAGEN_CHECKINS=$CHECKINS" -e "TICKET2H_DATAGEN_BIGEVENTORDERS=$BIG_EVENT_ORDERS" core-service

echo "Xong. Chạy lại hệ thống: docker compose --profile apps up -d"
echo "Xem sự kiện lớn (200.000 đơn): đăng nhập web bằng organizer1@test.local / Passw0rd!"

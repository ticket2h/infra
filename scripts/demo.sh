#!/usr/bin/env bash
# Kịch bản demo E1 trên cả hệ thống: mua 2 vé GA → thanh toán qua MockPay (webhook gửi trùng 3 lần) → vé
# → check-in → notification-service gửi email vé (kiểm tra qua API của Mailpit).
# Cần: docker compose up -d (trong infra), identity-service với profile dev (8082), core-service với profile dev
# (8080), notification-service (8081), mock-payment-gateway (9090). Cần jq, uuidgen.
# Đăng ký, đăng nhập gọi identity-service; mọi thứ khác gọi core-service bằng token identity phát.
set -euo pipefail

API=${API:-http://localhost:8080}
ID=${ID:-http://localhost:8082}
PAY=${PAY:-http://localhost:9090}
MAIL=${MAIL:-http://localhost:8025}
PASSWORD='Passw0rd!'

login() {
  curl -sf "$ID/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$PASSWORD\"}" | jq -r .accessToken
}

echo "== 0. Tìm sự kiện bằng từ khoá không dấu"
EVENT_ID=$(curl -sf "$API/events?q=son%20tung" | jq -r '.items[0].id')
GA_TYPE_ID=$(curl -sf "$API/events/$EVENT_ID" | jq -r '.ticketTypes[] | select(.kind=="GA") | .id')
echo "event=$EVENT_ID ga=$GA_TYPE_ID"

echo "== 1. Đăng ký khách mới rồi đăng nhập (mỗi lần chạy một khách, vì hạn mức 4 vé/người)"
BUYER="demo-$(uuidgen | cut -c1-8)@test.local"
curl -sf "$ID/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$BUYER\",\"password\":\"$PASSWORD\",\"fullName\":\"Khách demo\"}" > /dev/null
TOKEN=$(login "$BUYER")
AUTH="Authorization: Bearer $TOKEN"
echo "   $BUYER"

echo "== 2. Tạo đơn 2 vé GA"
KEY=$(uuidgen)
BODY="{\"eventId\":\"$EVENT_ID\",\"items\":[{\"ticketTypeId\":\"$GA_TYPE_ID\",\"quantity\":2}]}"
RESPONSE=$(curl -s "$API/orders" -H "$AUTH" -H 'Content-Type: application/json' -H "Idempotency-Key: $KEY" -d "$BODY")
ORDER_ID=$(jq -r '.orderId // empty' <<< "$RESPONSE")
[[ -n "$ORDER_ID" ]] || { echo "Tạo đơn thất bại: $RESPONSE" >&2; exit 1; }
echo "order: $ORDER_ID"

echo "== 2b. Gửi lại cùng key: phải 200 và cùng orderId"
curl -s -i "$API/orders" -H "$AUTH" -H 'Content-Type: application/json' -H "Idempotency-Key: $KEY" \
  -d "$BODY" | grep -iE '^HTTP|^idempotent-replayed'

echo "== 3. Bật chaos trên MockPay: mỗi webhook gửi 3 lần song song (áp dụng cho phiên tạo sau lệnh này)"
curl -sf -X PUT "$PAY/admin/chaos" -H 'Content-Type: application/json' -d '{"duplicateDeliveries":3}' | jq -c .

echo "== 4. Tạo thanh toán"
GW_ID=$(curl -sf -X POST "$API/orders/$ORDER_ID/payments" -H "$AUTH" | jq -r .gatewayPaymentId)
echo "gatewayPaymentId: $GW_ID"

echo "== 5. Hoàn tất thanh toán trên MockPay"
curl -sf -X POST "$PAY/admin/payments/$GW_ID/complete?result=SUCCESS" | jq -c '{status, gatewayTransactionId}'

echo "== 6. Chờ đơn PAID rồi FULFILLED"
for _ in $(seq 1 20); do
  STATUS=$(curl -sf "$API/orders/$ORDER_ID" -H "$AUTH" | jq -r .status)
  echo "   $STATUS"
  [[ "$STATUS" == "FULFILLED" ]] && break
  sleep 1
done

echo "== 7. Xem vé và tải QR"
TICKET_ID=$(curl -sf "$API/me/tickets" -H "$AUTH" | jq -r "[.[] | select(.orderId==\"$ORDER_ID\")][0].ticketId")
curl -sf "$API/tickets/$TICKET_ID/qr" -H "$AUTH" -o ticket.png && echo "   đã lưu ticket.png ($TICKET_ID)"

echo "== 8. notification-service đã gửi email vé cho $BUYER chưa? (hỏi API của Mailpit)"
# Chờ email TRƯỚC khi check-in: email lấy trạng thái vé lúc soạn, vé đã check-in thì không kèm QR nữa
SUBJECT=""
for _ in $(seq 1 20); do
  SUBJECT=$(curl -sfG "$MAIL/api/v1/search" --data-urlencode "query=to:$BUYER" | jq -r '.messages[0].Subject // empty' || true)
  [[ -n "$SUBJECT" ]] && break
  sleep 1
done
if [[ -n "$SUBJECT" ]]; then
  echo "   có email: \"$SUBJECT\". Xem tại $MAIL"
else
  echo "   CHƯA có email sau 20 giây. notification-service đang chạy chưa? Xem log của nó." >&2
  exit 1
fi

echo "== 9. Check-in bằng tài khoản STAFF được phân công (quét 2 lần)"
STAFF_TOKEN=$(login staff1@test.local)
QR=$(curl -sf "$API/dev/tickets/$TICKET_ID/qr-token" -H "$AUTH" | jq -r .qrToken)   # thay cho zbarimg
for gate in A1 B2; do
  curl -sf "$API/checkin" -H "Authorization: Bearer $STAFF_TOKEN" -H 'Content-Type: application/json' \
    -d "{\"qrToken\":\"$QR\",\"gate\":\"$gate\"}" | jq -c '{result, message}'
done

echo "== 10. MockPay đã gửi webhook mấy lần?"
curl -sf "$PAY/admin/webhook-deliveries?gatewayPaymentId=$GW_ID" | jq -c '[.[] | {deliveryNo, outcome, httpStatus}]'
curl -sf -X DELETE "$PAY/admin/chaos" > /dev/null

# Kiến trúc Ticket2h

## Hiện tại (sau bước 2, ngày 2026-10-16)

```
                       Client (curl, demo.sh; web-app :3000 qua nginx, ADR-015)
                 đăng ký, đăng nhập │                │ mọi API khác, kèm JWT
                                    ▼                ▼
                 identity-service :8082      core-service :8080 ◄──── webhook ký HMAC ────┐
                 tài khoản, ban tổ chức,     catalog, inventory, ordering,                 │
                 phát JWT (RS256)            payment, ticketing, outbox  ── X-Api-Key ──► mock-payment-gateway :9090
                   │  ▲   ▲   ▲                │      │                                   (không có database)
          database │  │   │   └── JWKS ────────┤      │ outbox → Kafka
          "identity"   │   └── POST /internal/users/lookup (tra email)
                   ▼  │                        ▼      ▼
              PostgreSQL     database "core"  PostgreSQL   ticket2h.ticket-events
                      │                                       │
                      │                                       ▼
                      └─── GET /internal/users/{id} ── notification-service :8081 ── GET /internal/tickets ──► core
                                                         │ database "notification"   │ SMTP
                                                         ▼                           ▼
                                                     PostgreSQL                Mailpit :1025 (xem ở :8025)
```

| Service | Làm gì | Dữ liệu riêng | Nói chuyện với ai |
|---|---|---|---|
| identity-service | Đăng ký, đăng nhập, phát JWT, quản trị tài khoản và ban tổ chức | database `identity` (`users`, `organizers`) | Công bố JWKS; cho core và notification gọi `/internal/users/**` |
| core-service | Sự kiện, giữ ghế, đơn, thanh toán, phát vé, check-in, chuyển nhượng | database `core` | Kiểm tra JWT bằng JWKS; tra email ở identity; gọi MockPay; nhận webhook; gửi event lên Kafka; cho notification gọi `/internal/tickets` |
| notification-service | Gửi email vé và email chuyển nhượng | database `notification` (sổ chống gửi trùng) | Nghe `ticket2h.ticket-events`; lấy email từ identity, vé từ core; gửi SMTP |
| mock-payment-gateway | Giả lập cổng thanh toán, có chế độ "chaos" | không (lưu trong bộ nhớ) | Nhận lệnh từ core; gửi webhook về core |

Ba hạ tầng dùng chung (PostgreSQL, Kafka, Mailpit) chạy bằng `docker compose` trong repo `infra`. PostgreSQL là
một server, nhưng mỗi service có **user và database riêng**, không đọc được bảng của nhau (ADR-012).

## Repo, CI và image

Mỗi service là một repo trong GitHub organization [`ticket2h`](https://github.com/ticket2h) (ADR-012, ADR-014):

```
push / pull request ──► GitHub Actions của repo đó: ./mvnw verify (Testcontainers)
push lên main, test xanh ──► build Dockerfile ──► ghcr.io/ticket2h/<repo>:latest, :sha-<commit>
                                                        │
infra: docker compose --profile apps up -d  ◄───────────┘  kéo 4 image, chạy cùng Postgres, Kafka, Mailpit
```

Repo nào cũng build và test được khi đứng một mình. Chạy cả hệ thống chỉ cần repo `infra`; sửa service nào thì clone
service đó, chạy bằng `./mvnw` cạnh các service khác chạy từ image.

## Vì sao tách như vậy

Theo "hướng A": giữ lõi đặt vé trong một service, chỉ tách phần ở rìa.

- **Lõi giữ nguyên**: tạo đơn, webhook thanh toán, phát vé, huỷ/hết hạn đều cần **một transaction** chạy qua
  nhiều module (đơn + ghế + vé GA + hạn mức + outbox). Các test M2 (`SeatClaimConcurrencyIT`,
  `GaInventoryConcurrencyIT`, `PurchaseQuotaConcurrencyIT`, `PaymentWebhookIT`...) vẫn chạy nguyên vẹn trong core.
- **Notification tách trước** (ADR-011): không ai gọi vào nó, nó chỉ nghe Kafka. Email chậm hay mail server sập
  không ảnh hưởng việc bán vé.
- **Identity tách thứ hai** (ADR-013): core chỉ cần biết "ai đang gọi" (có sẵn trong JWT đã ký) và thỉnh thoảng tra
  email. Đặt vé, thanh toán, check-in không gọi identity; identity tắt thì token đã phát vẫn dùng được, chỉ đăng nhập,
  chuyển nhượng và phân công soát vé tạm không làm được.

## Luồng mua vé qua các service

1. Khách gọi identity `POST /auth/login`, nhận JWT ký RS256 (claim `sub`, `role`, `organizerId` nếu là BTC).
2. Khách gọi core tạo đơn, tạo thanh toán. core kiểm tra JWT bằng public key lấy từ JWKS của identity (lấy một lần,
   giữ trong bộ nhớ). core gọi MockPay tạo phiên.
3. MockPay gửi webhook về core. core đánh dấu đơn PAID và ghi `OrderPaid` vào outbox trong **cùng transaction**.
4. Relay đẩy outbox lên `ticket2h.order-events`. Consumer **trong core** phát vé, ghi `TicketsIssued` vào outbox.
5. Relay đẩy `TicketsIssued` lên `ticket2h.ticket-events`.
6. notification-service nhận message (chỉ có id), hỏi identity email người mua, hỏi core thông tin vé và token QR,
   vẽ ảnh QR, gửi email.

Chuyển nhượng vé: core kiểm tra người gọi giữ vé, hỏi identity email người nhận (ngoài transaction), rồi đổi chủ vé
và ghi `TicketTransferred` vào outbox trong một transaction. notification gửi email cho cả hai người.

Topic `order-events` chỉ core dùng (gửi và nhận), nên không phải hợp đồng giữa các service. Hợp đồng giữa các
service: [`contracts.md`](contracts.md).

## Lộ trình tách tiếp

| Bước | Việc | Trạng thái |
|---|---|---|
| 1 | **notification-service**: email ra khỏi core; API nội bộ có khoá riêng; database riêng | Xong (2026-10-16) |
| 2 | **identity-service**: tài khoản ra khỏi core; JWT RS256 + JWKS; core bỏ khoá ngoại tới `users`/`organizers` | Xong (2026-10-16) |
| 3 | **api-gateway** (Spring Cloud Gateway): client chỉ gọi một cổng; chặn `/internal/**` từ bên ngoài | Chưa làm, cần duyệt thêm dependency |
| 3a | **web-app** (repo `web-app`, ADR-015): SPA React + momi-ui; nginx trong image web-app làm gateway tạm (`/api/identity`, `/api/core`, chặn `/internal`); refresh token cookie ở identity; OpenAPI ở identity và core | P0 xong (2026-10-18): đăng nhập, danh sách sự kiện |

Sau bước 3, các mốc M4–M6 của lộ trình (dữ liệu lớn, flash sale, vận hành) làm trên core-service.

Việc còn để ngỏ từ bước 2 (ADR-013): token sống 1 giờ và không thu hồi được (cần refresh token hoặc danh sách thu
hồi), chưa có quy trình đổi khoá ký JWT (JWKS đã sẵn sàng cho việc này).

# Hợp đồng giữa các service

Mỗi service là một repo riêng, **không dùng chung thư viện code**. Hai bên khớp nhau nhờ tài liệu này và test ở
cả hai phía. Đổi bất cứ thứ gì dưới đây là đổi hợp đồng: sửa tài liệu này, sửa cả producer lẫn consumer, chạy test
của cả hai repo.

## 1. Kafka: `ticket2h.ticket-events`

| | |
|---|---|
| Producer | core-service, qua outbox (ghi cùng transaction với thay đổi nghiệp vụ, relay đẩy lên sau) |
| Consumer | notification-service, consumer group `notification-service` |
| Partition | 3. Key = id của aggregate, nên các event của cùng một đơn/vé vào cùng partition, giữ thứ tự |
| Header | `eventType` (loại event), `eventId` (UUID, id dòng outbox) |
| Value | JSON object, UTF-8. Thời điểm dạng ISO-8601 UTC, ví dụ `"2026-11-01T12:00:00Z"` |
| Bảo đảm | **Ít nhất một lần** (at-least-once): cùng một event có thể tới nhiều lần, consumer phải idempotent |
| DLT | `ticket2h.ticket-events.DLT`, do notification-service khai báo và ghi (service nào consume thì sở hữu DLT) |

### `TicketsIssued` (key = `orderId`)

Đơn đã được phát vé.

```json
{ "orderId": "uuid", "userId": "uuid (người mua)", "ticketIds": ["uuid", "uuid"] }
```

### `TicketTransferred` (key = `ticketId`)

Vé đã chuyển sang người khác. QR cũ hết hiệu lực, QR mới có `tokenVersion` này.

```json
{ "ticketId": "uuid", "eventId": "uuid", "fromUserId": "uuid", "toUserId": "uuid",
  "tokenVersion": 2, "transferredAt": "2026-11-01T12:00:00Z" }
```

**Message không chứa token QR hay email.** Consumer cần thì gọi API nội bộ (mục 2). Lý do: ADR-011.

### Consumer xử lý thế nào

- Thiếu trường bắt buộc, không phải JSON, thiếu header `eventType`: message hỏng, vào DLT ngay, không thử lại.
- `eventType` lạ: bỏ qua (producer được phép thêm loại event mới).
- Trường lạ trong JSON: bỏ qua (producer được phép thêm trường).
- Lỗi tạm thời (mail server, core-service không trả lời): thử lại lùi dần (0,5s, 1s, 2s… tối đa 30s mỗi lần) trong
  10 phút, rồi vào DLT.

### Quy tắc thay đổi

| Thay đổi | Được không |
|---|---|
| Thêm trường mới vào payload | Được, consumer cũ bỏ qua |
| Thêm loại event mới | Được, consumer cũ bỏ qua |
| Đổi tên, xoá, đổi kiểu một trường | **Không.** Tạo loại event mới (ví dụ `TicketsIssuedV2`), gửi song song cả hai tới khi consumer chuyển xong |
| Đổi tên topic | **Không**, trừ khi dừng cả hệ thống để chuyển |

### Test giữ hợp đồng

- core-service: `TicketEventsContractIT` đọc message thật trên Kafka, kiểm tra key, header, đúng tập tên trường.
- notification-service: `IntegrationTest.publishTicketsIssued` / `publishTicketTransferred` gửi message giống hệt
  core; `TicketEventDltIT` kiểm tra message hỏng vào DLT.

## 2. Khoá API nội bộ (`X-Internal-Api-Key`)

Các API `/internal/**` chỉ dành cho service khác trong hệ thống, không dành cho người dùng. Sau này api-gateway sẽ
**không** chuyển tiếp đường dẫn `/internal/**` ra ngoài.

Mỗi service **gọi** có một khoá riêng, gửi trong header `X-Internal-Api-Key`. Service **được gọi** liệt kê khoá của
những service được phép (`ticket2h.internal-api.clients.<tên-service>`). JWT của người dùng, kể cả ADMIN, không mở
được các API này. Sai hoặc thiếu khoá: `401`, `code = UNAUTHENTICATED`.

| Service gọi | Biến chứa khoá | Được gọi tới |
|---|---|---|
| notification-service | `INTERNAL_API_KEY_NOTIFICATION` | core-service (`/internal/tickets`), identity-service (`/internal/users/{id}`) |
| core-service | `INTERNAL_API_KEY_CORE` | identity-service (`/internal/users/lookup`, `/internal/users/batch`) |

## 3. API nội bộ của core-service

### `GET /internal/tickets?ids={id},{id}...`

Gọi bởi: notification-service. Từ 1 đến 50 id (nhiều hơn: `400`). Vé không tồn tại thì không có trong kết quả.
Trả về `Cache-Control: no-store`.

```json
[ { "ticketId": "uuid", "orderId": "uuid", "eventId": "uuid", "ownerUserId": "uuid",
    "status": "VALID", "tokenVersion": 1,
    "eventTitle": "Sơn Tùng M-TP Live Concert 2026", "eventStartsAt": "2026-12-20T13:00:00Z",
    "eventTimeZone": "Asia/Ho_Chi_Minh", "ticketTypeName": "VIP", "seatLabel": "VIP A-12",
    "qrToken": "..." } ]
```

- `status`: `VALID`, `USED`, `VOID`. Consumer nên coi giá trị lạ là "không hợp lệ" thay vì lỗi.
- `qrToken`: chỉ có khi vé `VALID`, ngược lại là `null`. Đây là "chìa khoá vào cửa": không ghi log, không lưu.
- `seatLabel`: `null` với vé GA.

Test giữ hợp đồng: `InternalApiIT` ở core (khoá đúng/sai, JWT không mở được, token QR check-in được);
`FakeCoreApi` ở notification trả JSON đúng như trên.

## 4. API nội bộ của identity-service

Mỗi tài khoản trả cùng một dạng (`/batch` trả một mảng các tài khoản như vậy), `Cache-Control: no-store`:

```json
{ "id": "uuid", "email": "buyer@test.local", "fullName": "Nguyễn Văn An",
  "role": "CUSTOMER", "organizerId": null }
```

`role`: `CUSTOMER`, `ORGANIZER`, `STAFF`, `ADMIN` (bên gọi coi giá trị lạ là "không tìm thấy"). `organizerId` chỉ khác
`null` với `ORGANIZER`. Bên gọi bỏ qua trường nó không dùng.

### `GET /internal/users/{userId}`

Gọi bởi: notification-service (email và tên người nhận). Không có người dùng, hoặc id không phải UUID: `404`,
`code = NOT_FOUND`. (Đến M4 core-service cũng gọi API này cho danh sách nhân viên soát vé, mỗi người một lần; nay core
dùng `/batch` bên dưới.)

### `POST /internal/users/batch` với body `{"ids": ["uuid", ...]}` (M4)

Gọi bởi: core-service, mỗi lần tối đa 1.000 id: tên và email nhân viên soát vé (`GET /organizer/events/{id}/staff`),
người mua trong danh sách đơn (`GET /organizer/events/{id}/orders`, một lần mỗi trang) và trong file danh sách khách
(`attendees.csv`, một lần mỗi lô 1.000 vé: 500.000 khách là 500 lần gọi thay vì 500.000). Trả `200`
`{"users": [ ...dạng trên... ]}`, không theo thứ tự nào; id không có tài khoản (đã xoá, sai) thì **không có trong kết
quả**, không `404`, để một tài khoản đã xoá không làm hỏng cả lô. id trùng nhau coi như một. `ids` rỗng, thiếu, hoặc
hơn 1.000 id: `400 VALIDATION_FAILED`. core coi id không có trong kết quả là tài khoản đã bị xoá (nhân viên vẫn liệt
kê với `email`, `fullName` là `null`; người mua là "tài khoản không còn"); mã lỗi khác hoặc không trả lời: core báo
`502 IDENTITY_UNAVAILABLE` (file danh sách khách thử lại một lần trước khi bỏ cuộc).

### `POST /internal/users/lookup` với body `{"email": "..."}`

Gọi bởi: core-service (chuyển nhượng vé, phân công nhân viên soát vé). Email gửi trong **body** chứ không trên URL,
để không lọt vào log truy cập. identity chuẩn hoá (bỏ khoảng trắng hai đầu, chữ thường) trước khi tìm. Không có:
`404`; email trống hoặc sai dạng: `400 VALIDATION_FAILED`.

Test giữ hợp đồng: `InternalUserApiIT` ở identity; `FakeIdentity` ở core và `FakeIdentityApi` ở notification trả
JSON đúng như trên.

## 5. JWT và JWKS (identity-service phát, mọi service khác kiểm tra)

| | |
|---|---|
| Thuật toán | **RS256** duy nhất. Token ký bằng thuật toán khác (kể cả HS256) bị từ chối |
| Header | `alg: RS256`, `kid` (hiện là `k1`) |
| Claim | `iss` = `"ticket2h"` (chuỗi, không phải URL), `sub` = userId, `iat`, `exp` (1 giờ), `role`, và `organizerId` (UUID dạng chuỗi) chỉ khi `role = ORGANIZER` |
| Public key | `GET http://localhost:8082/.well-known/jwks.json` (trong compose: `http://identity-service:8082/...`; công khai, `Cache-Control: public, max-age=300`), chỉ có phần công khai (`kty`, `kid`, `use`, `alg`, `n`, `e`) |
| Private key | Chỉ identity-service giữ (`JWT_PRIVATE_KEY`) |

Service kiểm tra token (hiện là core-service):
- Lấy public key từ JWKS lúc gặp token đầu tiên rồi giữ trong bộ nhớ; gặp `kid` lạ thì tải lại. identity tắt thì
  token đã phát vẫn được kiểm tra bằng key đã giữ (đã thử ngày 2026-10-16), chỉ đăng nhập mới là không được.
- Chưa lấy được JWKS lần nào (service vừa khởi động) mà identity không trả lời: không kiểm tra được token → trả
  `502 IDENTITY_UNAVAILABLE` (ProblemDetail), **không** trả 401, vì token của khách có thể vẫn đúng.
- Kiểm tra: chữ ký, `iss`, `exp`/`nbf` (lệch tối đa 30 giây). Không gọi `Jwt.getIssuer()` của Spring vì `iss`
  không phải URL; dùng `JwtIssuerValidator("ticket2h")` hoặc `getClaimAsString("iss")`.
- Đọc người gọi từ claim: `sub`, `role`, `organizerId`. Không hỏi identity cho những thông tin này.

**Đổi khoá (sau này):** sinh khoá mới với `kid` mới, cho identity công bố cả hai khoá trong JWKS, ký bằng khoá mới,
chờ token cũ hết hạn (1 giờ) rồi bỏ khoá cũ. Service kiểm tra không phải sửa gì.

Test giữ hợp đồng: `JwtAndJwksIT` ở identity (token kiểm tra được chỉ bằng JWKS); `JwtVerificationIT` ở core
(khoá lạ, HS256, sai issuer bị từ chối).

## 6. Dữ liệu mẫu dùng chung (profile `dev`)

identity-service tạo tài khoản mẫu với **id cố định**; core-service tạo sự kiện mẫu cho đúng các id đó mà không gọi
identity lúc khởi động. Mật khẩu `Passw0rd!`.

| Id | Là gì |
|---|---|
| `0a000000-0000-4000-8000-000000000001` | Ban tổ chức "Sky Music Entertainment" (chủ sự kiện mẫu) |
| `0b000000-0000-4000-8000-000000000001` | `admin@test.local` (ADMIN) |
| `0b000000-0000-4000-8000-000000000002` | `organizer1@test.local` (ORGANIZER của Sky) |
| `0b000000-0000-4000-8000-000000000003` | `staff1@test.local` (STAFF, được phân công soát vé sự kiện mẫu) |
| `0b000000-0000-4000-8000-000000000004` … `…006` | `buyer1` … `buyer3@test.local` (CUSTOMER) |

Đổi các id này phải sửa cả `DevAccounts` (identity) lẫn `DevDataSeeder` (core).

### Dữ liệu sinh cho M4 (profile `datagen`, ADR-021)

`scripts/datagen.sh` chạy công cụ sinh của identity-service rồi của core-service với cùng các con số `customers`,
`organizers`, `staff`. Mỗi bên chỉ ghi database của mình; đơn của core trỏ đúng tài khoản identity đã sinh vì hai bên
tính id theo cùng công thức (`DatagenIds` ở cả hai repo, `i` đếm từ 1, viết hex 12 chữ số):

| Id | Là gì | Email (mật khẩu `Passw0rd!`) |
|---|---|---|
| `0e000000-0000-4000-8000-{i}` | Ban tổ chức thứ i | |
| `0c000000-0000-4000-8000-{i}` | Tài khoản ORGANIZER của ban tổ chức thứ i | `btc{i}@datagen.ticket2h.local` |
| `0f000000-0000-4000-8000-{i}` | Nhân viên soát vé thứ i | `soatve{i}@datagen.ticket2h.local` |
| `0d000000-0000-4000-8000-{i}` | Khách thứ i | `khach{i}@datagen.ticket2h.local` |

Ví dụ khách thứ 2.000.000: `0d000000-0000-4000-8000-0000001e8480`. Test giữ công thức: `DatagenIdsTest` ở identity và
`CoreDataGeneratorIT.shared_ids_match_the_contract` ở core kiểm tra cùng các giá trị. Sự kiện lớn đang mở bán (200.000
đơn) thuộc ban tổ chức mẫu Sky (`0a…01`) ở trên, để đăng nhập `organizer1@test.local` là xem được.

## 7. MockPay

API và webhook của MockPay: `mock-payment-gateway/docs/mockpay-spec.md`. Khoá API (`MOCKPAY_API_KEY`) và secret
ký webhook (`MOCKPAY_WEBHOOK_SECRET`) phải giống nhau ở core-service và MockPay.

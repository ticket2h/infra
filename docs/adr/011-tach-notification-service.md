# ADR-011: Tách notification-service, lấy dữ liệu qua API nội bộ thay vì nhét vào event

- Trạng thái: Đã chấp nhận. API `/internal/users/{id}` nay ở identity-service (ADR-013)
- Ngày: 2026-10-16

## Bối cảnh
Hệ thống chuyển sang microservice theo "hướng A": giữ lõi đặt vé trong một service, tách dần phần ở rìa. Email vé
là ứng viên đầu tiên: không module nào gọi vào nó, nó chỉ nghe `ticket-events` qua Kafka. Nhưng để soạn email, nó
cần ba thứ đang nằm trong database của core: **email người nhận**, **thông tin vé** và **token QR** (ký Ed25519,
không lưu trong database mà tính lại từ dữ liệu vé, ADR-008).

## Các phương án
1. **Event mang đủ dữ liệu** (event-carried state transfer): core nhét email, thông tin vé, token QR vào
   `TicketsIssued`. Notification không cần gọi ai.
2. **Event chỉ mang id, notification gọi API nội bộ của core** để lấy dữ liệu lúc xử lý.
3. **Notification đọc thẳng database của core** (chung database).
4. **Notification tự ký QR**: chia private key ký QR cho notification.

## Quyết định
Chọn phương án 2.

- Event `TicketsIssued`, `TicketTransferred` giữ nguyên như hồi còn monolith (chỉ có id).
- core-service mở `GET /internal/users/{id}` và `GET /internal/tickets?ids=...` (trả kèm `qrToken` của vé VALID).
- `/internal/**` có chuỗi bảo mật riêng: header `X-Internal-Api-Key`, mỗi service gọi một khoá riêng, so sánh thời
  gian hằng. JWT của người dùng không mở được (`InternalApiKeyFilter`, `SecurityConfig.internalApiFilterChain`).
- notification-service có database riêng chứa `notification_deliveries` (chống gửi trùng), consumer group riêng,
  và sở hữu `ticket2h.ticket-events.DLT`. core xoá bảng đó bằng migration mới `V113`.

Loại phương án 1 vì token QR là "chìa khoá vào cửa": nó sẽ nằm trong bảng `outbox_events` (giữ 7 ngày) và trong
log Kafka (giữ tới hết retention), ai đọc được topic là vào cửa được. Ngoài ra, email soạn từ dữ liệu cũ trong event
có thể gửi QR của vé đã chuyển nhượng cho người khác.
Loại phương án 3 vì hai service dùng chung bảng thì đổi bảng ở core sẽ làm hỏng notification mà không ai biết. Đó
là "monolith phân tán", mất lý do để tách.
Loại phương án 4 vì càng nhiều nơi giữ private key thì càng dễ lộ; lộ key thì kẻ xấu tự ký được vé.

## Đánh đổi
- **Phụ thuộc lúc chạy**: core-service sập thì notification không soạn được email. Lỗi gọi API được coi là lỗi
  tạm thời: error handler Kafka thử lại lùi dần trong 10 phút rồi đẩy vào DLT. Ngược lại, notification sập không
  ảnh hưởng gì tới core; bật lại thì email được gửi bù (đã thử bằng tay ngày 2026-10-16).
- **Email theo trạng thái lúc soạn**, không phải lúc phát vé. Vé đã check-in trước khi email kịp soạn sẽ không có
  QR trong email. Đây là ý muốn (QR vé đã dùng là vô dụng), nhưng thêm một chặng HTTP làm khoảng chờ dài hơn; demo
  vì thế chờ email trước rồi mới check-in.
- **Token QR đi qua HTTP nội bộ.** Máy local dùng HTTP thường. Khi deploy thật cần TLS giữa các service, hoặc
  mạng nội bộ không lộ ra ngoài.
- **Hợp đồng không còn được compiler kiểm tra.** Đổi tên một trường trong core không làm notification lỗi biên
  dịch. Thay bằng tài liệu `contracts.md` và test ở hai phía: `TicketEventsContractIT`, `InternalApiIT` (core),
  `FakeCoreApi` và các test email (notification).
- Một test acceptance của core (`CrashRecoveryIT.event_with_missing_fields_goes_to_dlt_without_long_retries`)
  kiểm tra hành vi của consumer email, nên đã chuyển sang `notification-service/.../acceptance/TicketEventDltIT`
  (người dùng đồng ý ngày 2026-10-16).

## Bằng chứng
- core-service: `./mvnw verify` xanh, 48 unit test + 119 integration test (các test M2 giữ nguyên).
- notification-service: `./mvnw verify` xanh, 12 test; ảnh QR trong email được giải mã lại và so khớp với token
  do core trả về.
- Chạy cả hệ thống bằng `infra/scripts/demo.sh`: đơn FULFILLED, email có 2 QR tới Mailpit, check-in OK rồi
  ALREADY_USED, chuyển nhượng gửi email cho cả hai người. Tắt notification-service: mua vé vẫn xong; bật lại thì
  email tới sau 8 giây.

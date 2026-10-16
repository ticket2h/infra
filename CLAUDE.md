# Ticket2h: infra

Hạ tầng local và tài liệu cấp hệ thống của Ticket2h (microservice). Các service là repo riêng (GitHub org `ticket2h`),
trên máy dev thường clone cạnh repo này: `../identity-service`, `../core-service`, `../notification-service`,
`../mock-payment-gateway`. Kiến trúc: `docs/kien-truc.md`.

## Lệnh
- Secret cho cả hệ thống: `scripts/init-env.sh` (tạo `.env`; compose đưa vào container, service chạy bằng `./mvnw` đọc `../infra/.env`)
- Hạ tầng: `docker compose up -d` (PostgreSQL, Kafka, Mailpit; project name `ticket2h`)
- Hạ tầng + 4 service từ image `ghcr.io/ticket2h/<repo>:latest`: `docker compose --profile apps up -d`
- Demo xuyên các service (cần cả 4 service đang chạy, identity và core với profile dev): `scripts/demo.sh`

## Quy tắc
- Đổi hợp đồng giữa các service (topic, header, trường JSON, API `/internal/**`, claim JWT, id dữ liệu mẫu) phải sửa `docs/contracts.md`,
  cả producer lẫn consumer, và chạy test của cả hai repo.
- Mỗi service một database và một user (`postgres/init/`). Không cho service đọc database của service khác.
- Quyết định ảnh hưởng nhiều service ghi thành ADR mới trong `docs/adr/` (đánh số tiếp từ 014). Không sửa ADR đã chấp nhận.
- Không commit `.env`, `*.pem`; `.env.example` chỉ liệt kê tên biến.
- Không thêm service hay dependency mới nếu chưa hỏi.
- Container trong compose gọi nhau bằng tên service (`http://core-service:8080`, `kafka:19092`); địa chỉ trình duyệt
  mở (return-url, link trong email, trang thanh toán MockPay) vẫn là `localhost`. Mỗi container chỉ nhận biến nó cần.
- Service mới phải chạy được ở cả hai cách: `./mvnw` trên máy (mặc định `localhost`) và profile `apps` (ghi đè bằng
  biến môi trường trong `docker-compose.yml`).

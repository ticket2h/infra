# Ticket2h: hạ tầng và tài liệu chung

[![CI](https://github.com/ticket2h/infra/actions/workflows/ci.yml/badge.svg)](https://github.com/ticket2h/infra/actions/workflows/ci.yml)

Ticket2h là hệ thống bán vé sự kiện, đang được tách dần thành microservice. Hệ thống tiếp nối dự án TicketRush
(M1–M3) trong `lo-trinh-backend-java.md` và `ticketrush-m2-m3-huong-dan.md`. Repo này không chứa code service. Nó chứa:

- `docker-compose.yml`: PostgreSQL, Kafka, Mailpit dùng chung khi chạy local; profile `apps` chạy thêm 4 service từ image
- `postgres/init/`: tạo user và database riêng cho từng service
- `scripts/init-env.sh`: sinh file `.env` chứa secret cho cả hệ thống
- `scripts/demo.sh`: kịch bản mua vé chạy qua mọi service
- `docs/`: kiến trúc, hợp đồng giữa các service, ADR cấp hệ thống

## Các repo

Mỗi service là một repo git riêng, có CI riêng (GitHub Actions: test, rồi build image lên GitHub Container Registry):

| Repo | Cổng | Vai trò |
|---|---|---|
| [`infra`](https://github.com/ticket2h/infra) | | repo này |
| [`identity-service`](https://github.com/ticket2h/identity-service) | 8082 | Đăng ký, đăng nhập, phát JWT (RS256), tài khoản và ban tổ chức |
| [`core-service`](https://github.com/ticket2h/core-service) | 8080 | Sự kiện, giữ chỗ, đơn hàng, thanh toán, vé, check-in, chuyển nhượng |
| [`notification-service`](https://github.com/ticket2h/notification-service) | 8081 | Nghe event vé trên Kafka, gửi email có QR |
| [`mock-payment-gateway`](https://github.com/ticket2h/mock-payment-gateway) | 9090 | MockPay, cổng thanh toán giả lập |

Chưa có api-gateway: đăng ký, đăng nhập gọi `:8082`, còn lại gọi `:8080`.

## Bắt đầu nhanh

Máy mới chưa có gì? Làm theo [`docs/chay-tren-may-moi.md`](docs/chay-tren-may-moi.md).

**Chạy thử cả hệ thống** (chỉ cần Docker, jq, openssl; không cần JDK, không cần clone service):

```bash
git clone https://github.com/ticket2h/infra.git && cd infra
scripts/init-env.sh                       # tạo .env với secret ngẫu nhiên (không commit)
docker compose --profile apps up -d       # hạ tầng + 4 service từ ghcr.io/ticket2h/*
scripts/demo.sh
```

**Sửa code một service**: clone repo đó cạnh `infra`, bật hạ tầng, chạy service bằng `./mvnw` (service tìm secret ở
`../infra/.env`). Các service còn lại chạy từ image hoặc cũng bằng `./mvnw`:

```bash
docker compose up -d                                                    # chỉ hạ tầng
cd ../identity-service && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev    # terminal 1: tài khoản mẫu
cd ../core-service && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev        # terminal 2: sự kiện mẫu
cd ../notification-service && ./mvnw spring-boot:run                               # terminal 3
cd ../mock-payment-gateway && ./mvnw spring-boot:run                               # terminal 4
cd ../infra && scripts/demo.sh                                                     # terminal 5
```

`demo.sh` đăng ký một khách mới ở identity, mua 2 vé ở core, thanh toán qua MockPay, chờ vé, kiểm tra email tới
Mailpit, rồi check-in. Email xem ở http://localhost:8025.

## Tài liệu

| Tài liệu | Nội dung |
|---|---|
| [`docs/kien-truc.md`](docs/kien-truc.md) | Các service, ai gọi ai, dữ liệu nằm ở đâu, lộ trình tách tiếp |
| [`docs/contracts.md`](docs/contracts.md) | Hợp đồng giữa các service: topic Kafka, API nội bộ, quy tắc thay đổi |
| [`docs/adr/`](docs/adr/README.md) | Quyết định kiến trúc cấp hệ thống (ADR-011 trở đi) |
| [`docs/chay-tren-may-moi.md`](docs/chay-tren-may-moi.md) | Chạy toàn bộ hệ thống từ máy trống, xử lý lỗi thường gặp |
| [`core-service/docs/`](https://github.com/ticket2h/core-service/tree/main/docs) | API, bảng dữ liệu, ADR-001…010, hướng dẫn học code |
| [`identity-service/README.md`](https://github.com/ticket2h/identity-service#readme) | API đăng nhập, JWT, JWKS, tài khoản mẫu |
| [`mock-payment-gateway/docs/mockpay-spec.md`](https://github.com/ticket2h/mock-payment-gateway/blob/main/docs/mockpay-spec.md) | Đặc tả MockPay |

## Lệnh hay dùng

| Muốn | Lệnh (trong `infra/`) |
|---|---|
| Bật hạ tầng | `docker compose up -d` |
| Bật hạ tầng và 4 service | `docker compose --profile apps up -d` |
| Cập nhật image service lên bản mới nhất trên `main` | `docker compose --profile apps pull` rồi `up -d` |
| Log của một service | `docker compose logs -f core-service` |
| Tắt, giữ dữ liệu | `docker compose --profile apps stop` |
| Xoá sạch, kể cả database | `docker compose --profile apps down -v` |
| Vào database của core | `docker compose exec postgres psql -U core` |
| Vào database của notification | `docker compose exec postgres psql -U notification` |
| Vào database của identity | `docker compose exec postgres psql -U identity` |
| Xem message Kafka | `docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic ticket2h.ticket-events --from-beginning --property print.headers=true` |
| Kiểm tra bất biến dữ liệu của core | `docker compose exec -T postgres psql -U core < ../core-service/scripts/invariants.sql` (cần repo core-service cạnh bên) |

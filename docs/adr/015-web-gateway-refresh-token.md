# ADR-015: Web SPA, gateway nginx trong image web-app, refresh token cookie, OpenAPI cho mọi service

- Trạng thái: Đã chấp nhận
- Ngày: 2026-10-18
- Liên quan: ADR-013 (JWT RS256, việc còn để ngỏ: token không thu hồi được), kiến trúc bước 3 (api-gateway)

## Bối cảnh
Hệ thống chưa có giao diện: client là curl và `scripts/demo.sh`. Làm web (repo `ticket2h/web-app`) gặp ba việc:

1. Trình duyệt phải gọi hai cổng (identity 8082, core 8080), cả hai chưa bật CORS.
2. Access token sống 1 giờ, không thu hồi được. Web giữ nó ở đâu: `localStorage` thì một lỗi XSS là mất token.
3. Kiểu dữ liệu của API chỉ có trong `docs/api.md`, gõ tay sang TypeScript thì lệch dần.

## Quyết định
- **Web là SPA React 19 + Vite**, thư viện giao diện `momi-ui` (cài từ git tag). Repo riêng `web-app`, cùng cách làm
  như các service: CI riêng, image `ghcr.io/ticket2h/web-app`, có trong `docker-compose.yml` (profile `apps`, cổng 3000).
- **Gateway cho trình duyệt là nginx nằm trong image web-app** (`web-app/nginx/default.conf.template`), không phải service
  Spring Cloud Gateway riêng: `/api/identity/**` → identity, `/api/core/**` → core, bỏ tiền tố. Chặn
  `/api/*/internal/**` và `/api/*/actuator/**` (404). Trình duyệt chỉ thấy một origin, nên không cần CORS.
  Khi dev, proxy của Vite làm y hệt.
- **Refresh token trong cookie** do identity-service phát: `ticket2h_refresh`, `HttpOnly; Secure; SameSite=Strict`,
  14 ngày, xoay vòng mỗi lần dùng (`POST /auth/refresh`), dùng lại token cũ thì thu hồi cả family, `POST /auth/logout`
  thu hồi. Database chỉ lưu SHA-256. Access token vẫn trả trong body `/auth/login` như cũ (curl, demo.sh không đổi);
  web giữ nó trong bộ nhớ và làm mới khi sắp hết hạn, tuần tự giữa các tab bằng Web Locks.
- **OpenAPI 3 bằng springdoc** (`springdoc-openapi-starter-webmvc-ui` 3.1.1) ở identity và core:
  `/v3/api-docs`, `/swagger-ui.html`. Web sinh kiểu TypeScript từ đó (`npm run api:types`) và commit kết quả.

## Đánh đổi
- nginx chỉ chuyển tiếp, không có rate limit, circuit breaker, kiểm tra JWT ở cửa. Đủ cho tới M5; khi cần những thứ
  đó thì làm api-gateway riêng (bước 3) và web chỉ còn phục vụ file tĩnh.
- Không có CORS nên web phải chạy sau gateway; mở web ở origin khác (ví dụ deploy tách) phải thêm CORS hoặc gateway.
- Cookie `Path` là đường dẫn trình duyệt thấy (`/api/identity/auth`), khác đường dẫn của service (`/auth`): gateway
  đổi bằng `proxy_cookie_path` (nginx) / `cookiePathRewrite` (Vite). Gọi thẳng cổng 8082 thì vẫn là `/auth`.
- Đóng một nửa việc để ngỏ của ADR-013: đăng xuất thu hồi được refresh token, nhưng access token đã phát vẫn sống tới
  khi hết hạn (tối đa 1 giờ). Rút ngắn TTL access token là bước sau, khi web đã dùng refresh ổn định.
- Record Java không mang thông tin bắt buộc/nullable, nên kiểu sinh ra để mọi trường response là tùy chọn. Web tự
  thu hẹp cho trường đã biết là NOT NULL; đánh dấu đúng ở BE (schema `required`, `nullable`) là việc tiếp theo.
- `/v3/api-docs` mở công khai trên service (không qua gateway vì đường dẫn đó không được chuyển). Tắt bằng
  `springdoc.api-docs.enabled=false` khi lên môi trường thật.

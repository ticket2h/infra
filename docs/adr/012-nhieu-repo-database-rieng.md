# ADR-012: Mỗi service một repo, một database; đổi tên hệ thống thành Ticket2h

- Trạng thái: Đã chấp nhận. Điều kiện "các repo phải nằm cạnh nhau" được bỏ ở ADR-014
- Ngày: 2026-10-16

## Bối cảnh
TicketRush M1–M3 là một repo Maven nhiều module (`app`, `mock-payment-gateway`) với một database. Khi chuyển sang
microservice, phải chọn: giữ một repo (monorepo) hay mỗi service một repo (polyrepo); dùng chung database hay tách.

## Quyết định
- **Polyrepo**: `infra`, `core-service`, `notification-service`, `mock-payment-gateway` là bốn repo git riêng, đặt
  cạnh nhau trong thư mục `ticket2h/`. Mỗi repo tự build (`./mvnw verify`), có `pom.xml` riêng kế thừa thẳng
  `spring-boot-starter-parent`, không có POM cha chung. Repo `ticketrush` cũ dừng ở M3, không sửa nữa.
- **Không dùng chung thư viện code giữa các service.** Class event (`TicketsIssued`...) được viết lại ở phía
  consumer. Hợp đồng nằm ở `infra/docs/contracts.md`.
- **Database-per-service trên một server PostgreSQL**: mỗi service một user và một database (`core`,
  `notification`), chỉ chủ database được kết nối (`REVOKE CONNECT ... FROM PUBLIC`). Service muốn dữ liệu của service
  khác thì gọi API hoặc nghe event.
- **Secret dùng chung ở `infra/.env`**: mỗi service đọc `../infra/.env`. Tiện cho chạy local; deploy thật thì mỗi
  service nhận biến môi trường riêng, chỉ những biến nó cần.
- **Đổi tên trong code**: package `com.ticket2h.*`, topic `ticket2h.*`, cấu hình `ticket2h.*`, tên hiển thị
  "Ticket2h". Lớp chính của lõi là `CoreServiceApplication`.

## Đánh đổi
- Polyrepo bắt mỗi service đứng độc lập: build, test, phiên bản riêng, nhìn rõ ranh giới. Đổi lại, một thay đổi
  chạm hai service phải làm ở hai repo, và không có compiler kiểm tra hợp đồng giữa chúng.
- Một server PostgreSQL chung là thoả hiệp cho máy local: tách quyền truy cập nhưng vẫn chung tài nguyên (CPU, ổ
  đĩa, thời điểm bảo trì). Deploy thật có thể tách server khi cần, code không phải đổi.
- Các service phải nằm cạnh nhau (`../infra/.env`) mới tìm thấy secret khi chạy local.
- Tài liệu lộ trình (`lo-trinh-backend-java.md`, `ticketrush-m2-m3-huong-dan.md`) vẫn gọi là TicketRush.

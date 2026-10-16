# ADR-014: Mỗi repo tự đứng được: CI riêng, image trên GHCR, infra chạy cả hệ thống từ image

- Trạng thái: Đã chấp nhận
- Ngày: 2026-10-16
- Bổ sung cho: ADR-012 (giữ polyrepo, bỏ điều kiện "các repo phải nằm cạnh nhau")

## Bối cảnh
ADR-012 chọn polyrepo nhưng để lại một ràng buộc: service chỉ tìm thấy secret khi repo `infra` nằm cạnh nó
(`../infra/.env`), tài liệu trỏ sang repo khác bằng đường dẫn `../infra/docs/...`, và muốn chạy cả hệ thống thì phải
clone đủ 5 repo rồi mở 4 terminal. Như vậy chưa phải polyrepo đúng nghĩa: một repo đứng riêng không chạy được, link
hỏng khi đọc trên GitHub, và người chỉ muốn chạy thử phải cài JDK, build cả bốn service.

Trước khi đẩy lên GitHub, đã cân nhắc gộp về một repo (monorepo). Chủ dự án chọn giữ polyrepo cho giống cách các
nhóm làm microservice ngoài thực tế: mỗi service một repo, một pipeline, một image.

## Quyết định
- **GitHub organization `ticket2h`**, mỗi repo một tên trùng tên thư mục: `infra`, `identity-service`, `core-service`,
  `notification-service`, `mock-payment-gateway`. Public.
- **Mỗi repo service có `.github/workflows/ci.yml`**: mỗi push và pull request chạy `./mvnw verify` (Testcontainers
  dùng Docker của runner). Push lên `main` mà test xanh thì build image và đẩy lên
  `ghcr.io/ticket2h/<repo>`, tag `latest` và `sha-<commit>`. Repo `infra` có CI kiểm tra `docker-compose.yml` và
  chạy shellcheck cho script.
- **Mỗi repo service có `Dockerfile`** hai bước: build bằng JDK 25 trong container (không cần Java trên máy), tách
  jar thành lớp (`-Djarmode=tools extract --layers`) để Docker cache phần thư viện, chạy bằng JRE 25 với user không
  phải root. Cấu hình và secret đến từ biến môi trường, không nằm trong image.
- **`infra/docker-compose.yml` có profile `apps`**: `docker compose --profile apps up -d` chạy hạ tầng và 4 service
  từ image, cùng cổng như khi chạy bằng `./mvnw`. Không có profile thì chỉ chạy hạ tầng, như trước. Container gọi
  nhau bằng tên service; địa chỉ trình duyệt mở (trang thanh toán, link trong email, return-url) vẫn là `localhost`.
  Mỗi container chỉ nhận những secret nó cần, không nhận cả file `.env`.
- **Kafka có hai listener**: `localhost:9092` cho service chạy trên máy, `kafka:19092` cho container.
- **Mỗi repo service có `.env.example`** chỉ liệt kê biến nó cần (không có giá trị). Service đọc `../infra/.env` nếu
  có (tiện khi clone cạnh `infra`), rồi `.env` của chính repo, rồi biến môi trường: không bắt buộc repo nào nằm cạnh
  repo nào.
- **Link giữa các repo là link GitHub**, không phải đường dẫn `../`. Lệnh shell trong tài liệu vẫn có thể dùng
  `../infra` khi đã ghi rõ là repo đó được clone cạnh bên. `CLAUDE.md` giữ đường dẫn `../` vì agent làm việc trên
  máy dev có đủ các repo.

## Đánh đổi
- Mỗi service phải giữ ba thứ giống nhau (Dockerfile, workflow, `.env.example`). Sửa một thì phải sửa cả bốn; chưa
  đáng tách ra thành workflow dùng chung (reusable workflow) khi mới có bốn repo.
- Image `latest` của `main` không gắn với một phiên bản cụ thể của service khác: chạy thử thì đủ, deploy thật cần
  ghim tag `sha-...` (biến `TICKET2H_TAG` trong compose) và kiểm tra hợp đồng giữa các phiên bản.
- Package GHCR mặc định là private khi CI đẩy lần đầu; phải chuyển sang public một lần cho mỗi package thì người khác
  mới `docker compose pull` được mà không cần đăng nhập.
- Chạy trộn (một service từ IDE, phần còn lại từ image) chỉ đúng với service không bị container khác gọi tới theo
  tên. core-service chạy ngoài Docker thì MockPay và notification-service trong container không gọi được nó.
- Đổi hợp đồng giữa hai service vẫn phải làm ở hai repo, hai pull request; CI của mỗi repo chỉ chạy test của repo đó
  (test hợp đồng dùng server giả). Chưa có CI chạy cả hệ thống (`demo.sh` trên compose): để sau.

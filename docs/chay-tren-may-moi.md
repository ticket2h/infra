# Chạy Ticket2h trên máy mới

Làm lần lượt 7 bước dưới đây, từ một máy chưa có gì tới lúc mua được vé, nhận email và check-in. Lần đầu mất khoảng
20–30 phút, phần lớn là chờ tải công cụ, thư viện Maven và image Docker.

Ticket2h gồm **4 service + hạ tầng**, mỗi phần một repo trên GitHub (https://github.com/ticket2h):

| Repo | Cổng | Vai trò |
|---|---|---|
| [`infra`](https://github.com/ticket2h/infra) | | PostgreSQL, Kafka, Mailpit (Docker); chạy cả hệ thống từ image; secret; script demo |
| [`identity-service`](https://github.com/ticket2h/identity-service) | 8082 | Đăng ký, đăng nhập, phát JWT; tài khoản và ban tổ chức |
| [`core-service`](https://github.com/ticket2h/core-service) | 8080 | Lõi: sự kiện, giữ ghế, đơn hàng, thanh toán, vé, check-in, chuyển nhượng |
| [`notification-service`](https://github.com/ticket2h/notification-service) | 8081 | Nghe event vé trên Kafka, gửi email có QR |
| [`mock-payment-gateway`](https://github.com/ticket2h/mock-payment-gateway) | 9090 | MockPay, cổng thanh toán giả lập |

Có hai cách chạy, chọn theo việc bạn muốn làm:

- **Chỉ chạy thử cả hệ thống**: chỉ cần repo `infra` và Docker. Bốn service chạy từ image mà CI của từng repo đã
  build sẵn (Bước 5, Cách A). Không cần JDK, không cần clone code service.
- **Đọc, sửa, debug code**: clone thêm repo service muốn làm, đặt cạnh `infra`, chạy bằng `./mvnw` hoặc IntelliJ
  (Bước 5, Cách B, C). Có thể trộn: service đang sửa chạy từ IDE, phần còn lại chạy từ image.

Hướng dẫn viết cho Ubuntu/Linux. Windows và macOS xem ghi chú ở cuối Bước 1.

---

## Bước 1. Cài công cụ

| Công cụ | Để làm gì | Bắt buộc |
|---|---|---|
| Git | Tải code về | Có |
| JDK 25 | Biên dịch và chạy Java | Khi chạy service bằng `./mvnw`/IDE và khi chạy test |
| Docker + Docker Compose | Chạy PostgreSQL, Kafka, Mailpit; chạy test | Có |
| curl, jq, uuidgen, openssl | Script `init-env.sh` và `demo.sh` | Có |
| IntelliJ IDEA (hoặc STS, VS Code) | Đọc, sửa, chạy, debug code | Nên có |
| DBeaver | Xem dữ liệu trong database | Tuỳ chọn |

Maven **không** cần cài: mỗi repo có sẵn `./mvnw` (Maven wrapper), tự tải đúng phiên bản Maven lần đầu chạy.

**Ubuntu:**

```bash
sudo apt update
sudo apt install git openjdk-25-jdk curl jq uuid-runtime openssl
```

**Docker**, chọn một trong hai:

- **Docker Desktop** (có giao diện): tải ở https://docs.docker.com/desktop/setup/install/linux/
- **Docker Engine** (chỉ dòng lệnh, nhẹ hơn):
  ```bash
  sudo apt install docker.io docker-compose-v2
  sudo usermod -aG docker $USER      # cho phép chạy docker không cần sudo
  ```
  Sau lệnh `usermod`, **đăng xuất rồi đăng nhập lại** để quyền có hiệu lực.

**Kiểm tra** (mỗi lệnh phải chạy không lỗi):

```bash
git --version
java -version              # phải là 25.x
docker run --rm hello-world
docker compose version
```

**Windows / macOS:**
- Cài Docker Desktop, JDK 25 (ví dụ Eclipse Temurin từ https://adoptium.net), Git.
- Các file `.sh` chạy bằng Git Bash hoặc WSL. Trên Windows dùng `mvnw.cmd` thay cho `./mvnw`.

---

## Bước 2. Tải repo về

Tạo một thư mục cha rồi clone vào đó. **Chỉ chạy thử** thì chỉ cần `infra`:

```bash
mkdir -p ~/personal-projects/ticket2h && cd ~/personal-projects/ticket2h
git clone https://github.com/ticket2h/infra.git
```

**Sửa code** thì clone thêm repo service cần sửa (hoặc cả bốn), đặt **cạnh** `infra`:

```bash
cd ~/personal-projects/ticket2h
for repo in identity-service core-service notification-service mock-payment-gateway; do
  git clone https://github.com/ticket2h/$repo.git
done
```

```
ticket2h/
├── infra/
├── identity-service/
├── core-service/
├── notification-service/
└── mock-payment-gateway/
```

Đặt cạnh nhau chỉ để tiện: service chạy bằng `./mvnw` tìm secret ở `../infra/.env` nếu có. Mỗi repo vẫn tự build và
chạy test được khi đứng một mình; khi đó chép `.env.example` của repo thành `.env` và điền giá trị (giá trị phải khớp
với `infra/.env`, xem Bước 3).

---

## Bước 3. Tạo file `.env` chứa secret

```bash
cd ~/personal-projects/ticket2h/infra
scripts/init-env.sh
```

Lệnh này sinh `infra/.env` với các giá trị ngẫu nhiên:

| Biến | Ai dùng | Để làm gì |
|---|---|---|
| `MOCKPAY_API_KEY` | core, MockPay | Core xác thực khi gọi MockPay |
| `MOCKPAY_WEBHOOK_SECRET` | core, MockPay | Ký và kiểm tra chữ ký webhook thanh toán |
| `JWT_PRIVATE_KEY` | identity | Khoá RSA ký token đăng nhập. Chỉ identity đọc; service khác lấy public key qua JWKS |
| `QR_PRIVATE_KEY`, `QR_PUBLIC_KEY` | core | Cặp khoá Ed25519 ký QR vé |
| `INTERNAL_API_KEY_NOTIFICATION` | notification, core, identity | notification-service gọi API nội bộ `/internal/**` của core và identity |
| `INTERNAL_API_KEY_CORE` | core, identity | core-service gọi API nội bộ của identity (tra email) |

- Chạy bằng Docker (Cách A): `docker compose` đọc `infra/.env` và đưa cho mỗi container **chỉ những biến nó cần**.
- Chạy bằng `./mvnw`/IDE (Cách B, C): service **tự đọc** `../infra/.env` khi khởi động, không cần đặt biến môi
  trường trong IDE. Repo không nằm cạnh `infra` thì service đọc `.env` trong chính repo đó (mẫu: `.env.example`).
- `.env` đã nằm trong `.gitignore`: **không bao giờ commit** file này. `.env.example` là bản mẫu không có giá trị.
- Chạy lại `scripts/init-env.sh --force` sẽ sinh secret mới. Sau đó phải **khởi động lại cả bốn service**, nếu không
  chúng dùng hai bộ secret khác nhau: webhook bị từ chối, API nội bộ trả 401, token cũ không còn hợp lệ.

---

## Bước 4. Bật hạ tầng: PostgreSQL, Kafka, Mailpit

```bash
cd ~/personal-projects/ticket2h/infra
docker compose up -d
docker compose ps
```

Kết quả mong đợi (postgres, kafka chuyển sang `healthy` sau vài giây):

```
ticket2h-kafka-1      Up (healthy)
ticket2h-mailpit-1    Up (healthy)
ticket2h-postgres-1   Up (healthy)
```

Tên container luôn bắt đầu bằng `ticket2h-` (đặt bằng `name:` trong `docker-compose.yml`), không phụ thuộc tên thư mục.

| Dịch vụ | Địa chỉ | Thông tin |
|---|---|---|
| PostgreSQL | `localhost:5432` | database `core`, `notification`, `identity`, mỗi database có user và mật khẩu trùng tên; quản trị: `postgres`/`postgres` |
| Kafka | `localhost:9092` | Container trong compose dùng `kafka:19092` |
| Mailpit (xem email) | http://localhost:8025 | SMTP ở `localhost:1025` |

Lần đầu bật, PostgreSQL chạy `postgres/init/01-databases.sql` để tạo ba user và ba database. Các database lúc
này còn **trống**: bảng do Flyway của từng service tạo khi service đó khởi động.

> Máy còn container của repo `ticketrush` cũ đang chạy thì sẽ báo `port is already allocated`. Tắt chúng trước:
> `docker stop ticketrush-postgres-1 ticketrush-kafka-1 ticketrush-mailpit-1`.

---

## Bước 5. Chạy 4 service

Thứ tự khởi động không quan trọng, nhưng cả bốn phải chạy cùng lúc. identity-service và core-service chạy với
profile `dev`: identity tạo tài khoản mẫu, core tạo sự kiện mẫu cho các tài khoản đó (id cố định, xem
`contracts.md` mục 6). Chọn một trong ba cách.

### Cách A: Docker, không cần code (một lệnh)

```bash
cd ~/personal-projects/ticket2h/infra
docker compose --profile apps up -d     # hạ tầng + 4 service từ ghcr.io/ticket2h/*:latest
docker compose --profile apps ps        # 7 container
docker compose logs -f core-service     # xem log một service
```

Profile `apps` bật thêm 4 container `identity-service`, `core-service`, `notification-service`,
`mock-payment-gateway`, cùng cổng như khi chạy bằng `./mvnw`. Lần đầu tải 4 image mất vài phút. Muốn chạy bản mới
nhất trên `main`: `docker compose --profile apps pull` rồi `up -d` lại. Tắt: `docker compose --profile apps stop`.

**Sửa một service, các service khác chạy từ image:** tắt container của service đó rồi chạy nó bằng Cách B hoặc C:

```bash
docker compose --profile apps up -d
docker compose stop core-service        # cổng 8080 trống
cd ../core-service && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev
```

Riêng notification-service (gọi core) và core-service (nhận webhook của MockPay) tìm service khác theo **tên trong
compose**. Khi core-service chạy ngoài Docker, email vé và webhook không tới được nó; thử luồng đó thì chạy cả hai
phía bằng Cách B.

Build image từ code đang có trên máy thay vì tải về (ví dụ để thử Dockerfile):
`docker build -t ghcr.io/ticket2h/core-service:latest ../core-service`, rồi `docker compose --profile apps up -d`.

### Cách B: dòng lệnh (4 cửa sổ terminal)

```bash
# Terminal 1: identity-service (cổng 8082), profile dev tạo tài khoản mẫu
cd ~/personal-projects/ticket2h/identity-service && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev

# Terminal 2: core-service (cổng 8080), profile dev tạo sự kiện mẫu
cd ~/personal-projects/ticket2h/core-service && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev

# Terminal 3: notification-service (cổng 8081)
cd ~/personal-projects/ticket2h/notification-service && ./mvnw spring-boot:run

# Terminal 4: MockPay (cổng 9090)
cd ~/personal-projects/ticket2h/mock-payment-gateway && ./mvnw spring-boot:run
```

Chờ các dòng `Started IdentityServiceApplication`, `Started CoreServiceApplication`,
`Started NotificationServiceApplication`, `Started MockPayApplication`. identity in danh sách tài khoản mẫu; core in
`EVENT_ID`, `GA_TYPE_ID`, `VIP_TYPE_ID`. Lần đầu Maven tải thư viện, có thể mất vài phút. Tắt: Ctrl+C trong từng terminal.

### Cách C: IntelliJ IDEA (một cửa sổ cho cả hệ thống)

1. **File → Open…** → chọn thư mục `ticket2h` (thư mục cha, không phải từng repo) → **Trust Project**.
2. Mở cửa sổ **Maven** (thanh bên phải) → nút **+** (*Add Maven Projects*) → chọn `pom.xml` của
   `identity-service`. Lặp lại cho `core-service`, `notification-service` và `mock-payment-gateway`. Chờ *Indexing…/Syncing…* chạy xong.
3. **File → Project Structure → Project → SDK** chọn JDK 25 (Ubuntu: `/usr/lib/jvm/java-25-openjdk-amd64`).
4. Chạy từng service: Shift hai lần, gõ tên class, Enter, bấm ▶ cạnh `public class ...` → **Run**:
   - `MockPayApplication`
   - `NotificationServiceApplication`
   - `IdentityServiceApplication` và `CoreServiceApplication`: bấm ▶ → **Modify Run Configuration…** → ô
     **Active profiles** nhập `dev` (không thấy ô này: **Modify options** → bật lên) → **OK** → chạy.
5. Kiểm tra **Working directory** của mỗi cấu hình chạy là thư mục của repo đó (ví dụ `.../ticket2h/core-service`),
   nếu không service sẽ không tìm thấy `../infra/.env`. Đây là mặc định của IntelliJ.
6. Cửa sổ **Services** (Alt+8) gom cả bốn service: bật, tắt, xem log ở một chỗ.

Mỗi repo vẫn là một git repo riêng: IntelliJ nhận cả năm trong **Git → Manage Remotes / Commit** (chọn repo khi commit).

---

## Bước 6. Kiểm tra mọi thứ chạy

```bash
cd ~/personal-projects/ticket2h/infra
scripts/demo.sh
```

Script đăng ký một khách mới ở identity-service, mua 2 vé GA ở core-service, thanh toán qua MockPay (webhook gửi trùng 3 lần), chờ phát vé, **chờ email
từ notification-service tới Mailpit**, rồi check-in hai lần. Kết quả mong đợi ở cuối:

```
== 6. Chờ đơn PAID rồi FULFILLED
   FULFILLED
== 8. notification-service đã gửi email vé cho demo-xxxxxxxx@test.local chưa? (hỏi API của Mailpit)
   có email: "Vé của bạn: Sơn Tùng M-TP Live Concert 2026". Xem tại http://localhost:8025
== 9. Check-in bằng tài khoản STAFF được phân công (quét 2 lần)
{"result":"OK","message":"Hợp lệ, mời vào"}
{"result":"ALREADY_USED","message":"Vé đã được sử dụng lúc ... tại cổng A1"}
```

Sau đó:
- Mở http://localhost:8025: email "Vé của bạn: …" có 2 ảnh QR.
- Xem dữ liệu bằng DBeaver: **Database → New Database Connection → PostgreSQL**, host `localhost`, port `5432`.
  Tạo ba kết nối: database `core`, `notification`, `identity`, mỗi cái user và mật khẩu trùng tên database.
  Lần đầu bấm **Download** khi được hỏi tải driver.

`demo.sh` chạy được với cả ba cách ở Bước 5 vì cổng giống nhau.

**Thử tính độc lập của service:** tắt notification-service (Cách A: `docker compose stop notification-service`), chạy `scripts/demo.sh`. Đơn vẫn `FULFILLED`, script
báo "CHƯA có email". Bật lại notification-service: vài giây sau email tới Mailpit.

**Thử identity tắt:** tắt identity-service. Token đã đăng nhập vẫn dùng được ở core (core đã giữ public key), mua vé
vẫn được; chỉ đăng nhập, chuyển nhượng vé và phân công soát vé báo lỗi (502 `IDENTITY_UNAVAILABLE`), không đổi dữ liệu.

Tài khoản mẫu (mật khẩu `Passw0rd!`): [identity-service README](https://github.com/ticket2h/identity-service#readme).
Danh sách API: [identity-service README](https://github.com/ticket2h/identity-service#readme),
[core-service/docs/api.md](https://github.com/ticket2h/core-service/blob/main/docs/api.md).

---

## Bước 7. Chạy test

Mỗi repo chạy test riêng:

```bash
cd ~/personal-projects/ticket2h/identity-service && ./mvnw verify       # 27 test
cd ~/personal-projects/ticket2h/core-service && ./mvnw verify           # khoảng 170 test, 2–3 phút
cd ~/personal-projects/ticket2h/notification-service && ./mvnw verify   # 13 test
cd ~/personal-projects/ticket2h/mock-payment-gateway && ./mvnw verify   # 48 test
```

Test tự bật PostgreSQL và Kafka **riêng** bằng Testcontainers (cần Docker), không đụng tới dữ liệu ở Bước 4, và
không cần service nào đang chạy. Service khác được thay bằng HTTP server giả: core dùng `FakeIdentity` (JWKS và tra
email), notification dùng `FakeCoreApi` và `FakeIdentityApi`. Lần đầu lâu hơn vì phải tải image cho test.

Trên GitHub, mỗi repo chạy đúng các lệnh này ở mỗi lần push và pull request (tab **Actions**, file
`.github/workflows/ci.yml`). Push lên `main` mà test xanh thì CI build image và đẩy lên `ghcr.io/ticket2h/<repo>`:
đó là image Cách A ở Bước 5 tải về.

Chạy một class test: `./mvnw test -Dtest=RequestHashTest` (unit test) hoặc
`./mvnw verify -Dit.test=CheckinIT` (integration test, tên kết thúc bằng `IT`). Trong IntelliJ: bấm ▶ cạnh tên class test.

---

## Hằng ngày: bật, tắt, dọn

| Muốn | Lệnh (trong `infra/`) |
|---|---|
| Bật hạ tầng (mỗi lần mở máy) | `docker compose up -d` |
| Tắt hạ tầng, giữ dữ liệu | `docker compose stop` |
| Xoá container, giữ dữ liệu | `docker compose down` |
| Xoá sạch, kể cả dữ liệu database | `docker compose down -v` |
| Xem log Postgres | `docker compose logs -f postgres` |
| Vào database bằng dòng lệnh | `docker compose exec postgres psql -U core` (hoặc `-U notification`, `-U identity`) |

Lần sau mở máy chỉ cần: `docker compose up -d` trong `infra`, rồi chạy 4 service (Bước 5); hoặc gộp cả hai:
`docker compose --profile apps up -d`. Lệnh `stop`, `down` thêm `--profile apps` để tắt cả container service.

---

## Gặp lỗi

| Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|
| `permission denied ... docker.sock` | User chưa thuộc nhóm `docker` | `sudo usermod -aG docker $USER`, đăng xuất rồi đăng nhập lại |
| Tải image báo `network is unreachable` hoặc timeout | Mạng chập chờn (Docker Desktop đôi khi thử IPv6) | Chạy lại `docker compose up -d` |
| `port is already allocated` (5432, 9092, 8025...) | Chương trình khác (hoặc container `ticketrush-*` cũ) đang dùng cổng | Tắt chương trình kia; hoặc đổi cổng bên trái trong `docker-compose.yml` (`"5433:5432"`) và sửa URL trong `application.yml` của các service |
| `Port 8080 / 8081 / 8082 / 9090 was already in use` | Service đó đang chạy ở chỗ khác, kể cả container của profile `apps` | Tắt bản cũ (Ctrl+C, nút ■ trong IntelliJ, `docker compose stop <tên-service>`) |
| `docker compose --profile apps up` báo `denied` hoặc `manifest unknown` khi tải `ghcr.io/ticket2h/...` | Image chưa có (CI của repo đó chưa chạy xong lần nào) hoặc package trên GitHub đang để private | Chờ CI xanh; hoặc build tại máy: `docker build -t ghcr.io/ticket2h/<repo>:latest ../<repo>` |
| Service báo thiếu `MOCKPAY_API_KEY`, `JWT_PRIVATE_KEY`, `INTERNAL_API_KEY_CORE`... | Chưa có `infra/.env`, `.env` sinh từ phiên bản script cũ, hoặc repo không nằm cạnh `infra` (và không có `.env` riêng) | `infra/scripts/init-env.sh --force` rồi khởi động lại mọi service; kiểm tra cấu trúc thư mục ở Bước 2 và working directory ở Bước 5 |
| `password authentication failed for user "identity"` (hoặc `core`, `notification`), `database "identity" does not exist` | Volume `pgdata` được tạo trước khi có dòng tạo user/database đó (script `postgres/init` chỉ chạy khi volume trống) | Giữ dữ liệu: chạy tay các dòng `CREATE USER`/`CREATE DATABASE` còn thiếu trong `postgres/init/01-databases.sql` bằng `docker compose exec postgres psql -U postgres`. Không cần giữ: `docker compose down -v` rồi `up -d` |
| Mọi API cần đăng nhập của core trả 502 `IDENTITY_UNAVAILABLE` "Tạm thời không kiểm tra được đăng nhập" | core vừa khởi động, chưa lấy được public key (JWKS) lần nào, mà identity-service không chạy | Bật identity-service rồi gọi lại; core tự lấy JWKS ở request kế tiếp |
| Mọi API cần đăng nhập của core trả 401 dù vừa đăng nhập | Token ký bằng khoá cũ (vừa chạy `init-env.sh --force`), hoặc đồng hồ máy lệch | Đăng nhập lại để lấy token mới; khởi động lại identity nếu chưa |
| Chuyển nhượng vé hoặc phân công soát vé trả 502 `IDENTITY_UNAVAILABLE` | identity-service không chạy, hoặc core và identity khác `INTERNAL_API_KEY_CORE` | Bật identity-service; xem log core dòng "Tra tài khoản ở identity-service thất bại" |
| Demo dừng ở bước đăng ký với `curl: (7) Failed to connect to localhost port 8082` | identity-service chưa chạy | Bật identity-service (Bước 5) |
| `Connection to localhost:5432 refused` | PostgreSQL chưa chạy | `docker compose up -d` |
| Log liên tục `Connection to node -1 ... could not be established` | Kafka chưa chạy | `docker compose up -d` |
| Demo dừng ở `PENDING_PAYMENT`, không thấy `PAID` | MockPay không chạy, hoặc core và MockPay dùng `.env` khác nhau | Kiểm tra MockPay; sau khi chạy lại `init-env.sh` thì khởi động lại cả ba service |
| Demo báo `CHƯA có email sau 20 giây` | notification-service không chạy, hoặc bị core/identity trả 401 | Xem log notification-service; dòng `... từ chối khoá API nội bộ` nghĩa là các service khác `INTERNAL_API_KEY_NOTIFICATION`: khởi động lại tất cả |
| Email có ít QR hơn số vé | Vé đã check-in (hoặc đã chuyển nhượng) trước khi email kịp soạn | Đúng thiết kế (ADR-011): QR của vé đã dùng thì không gửi |
| `./mvnw: Permission denied` | Mất quyền chạy file (hay gặp khi chép từ Windows) | `chmod +x mvnw scripts/*.sh` trong repo đó |
| `release version 25 not supported` | Maven hoặc IDE đang dùng JDK cũ hơn 25 | Cài JDK 25; trong IntelliJ chọn SDK 25 (Bước 5, Cách C) |
| Test báo `Could not find a valid Docker environment` | Docker chưa chạy hoặc chưa có quyền | Mở Docker Desktop / `sudo systemctl start docker`; kiểm tra `docker run --rm hello-world` |

Muốn hiểu code sau khi chạy được: đọc
[core-service/docs/huong-dan-hoc-code.md](https://github.com/ticket2h/core-service/blob/main/docs/huong-dan-hoc-code.md),
rồi [`kien-truc.md`](kien-truc.md) và [`contracts.md`](contracts.md) trong thư mục này.

# ADR-013: Tách identity-service; core tin JWT RS256 qua JWKS, không giữ bản sao người dùng

- Trạng thái: Đã chấp nhận
- Ngày: 2026-10-16

## Bối cảnh
Bước 2 của "hướng A": tài khoản (đăng ký, đăng nhập, ban tổ chức, quản trị) ra khỏi core thành identity-service với
database riêng. Có ba chỗ phải quyết:

1. **Dữ liệu người dùng mà core cần.** Database core có 10 khoá ngoại trỏ tới `users`/`organizers` (đơn, vé, hạn mức,
   chuyển nhượng, check-in, sự kiện, địa điểm, nhân viên soát vé). Ngoài khoá ngoại, core cần: ban tổ chức của người
   gọi (mọi API `/organizer/**`), và tra tài khoản theo email (chuyển nhượng vé, phân công soát vé).
2. **JWT.** Trước đây core vừa phát vừa kiểm tra token HS256 bằng một secret. Nếu identity phát và core kiểm tra mà vẫn
   dùng HS256, cả hai phải giữ cùng secret, và ai có secret cũng **tự phát** được token với vai trò bất kỳ.
3. **Thời điểm gọi identity.** Tra email là lời gọi HTTP; quy tắc của core cấm gọi mạng trong transaction.

## Các phương án
Cho chỗ 1:
- A. Core giữ **bảng sao chép** `users` (id, email, vai trò, ban tổ chức), identity bắn event khi tạo/sửa tài khoản.
  Giữ được khoá ngoại và tra email trong cùng database. Nhưng: tài khoản vừa đăng ký có thể chưa kịp sang core khi
  khách đặt vé ngay sau đó (event đi qua outbox → Kafka mất khoảng 1 giây), khoá ngoại sẽ chặn tạo đơn.
- B. **Không sao chép.** Bỏ khoá ngoại; id người dùng lấy từ JWT đã ký nên tin được. Thông tin của chính người gọi
  nằm sẵn trong token (vai trò, ban tổ chức). Tra email thì gọi API của identity.

Cho chỗ 2:
- HS256 với secret dùng chung; hoặc **RS256**: identity ký bằng private key, core kiểm tra bằng public key lấy từ
  **JWKS** (`/.well-known/jwks.json`, chuẩn của OAuth2/OpenID).

## Quyết định
- **Phương án B.** Migration `V114` của core bỏ 10 khoá ngoại và xoá bảng `users`, `organizers`. Index trên các cột
  `user_id`, `organizer_id` giữ nguyên. Không có bảng sao chép, không có event tài khoản.
- **JWT RS256 + JWKS.** Chỉ identity giữ private key (`JWT_PRIVATE_KEY`). core chỉ có `JwtDecoder` lấy key từ
  `ticket2h.jwt.jwk-set-uri`, chỉ chấp nhận RS256 (token HS256 kiểu cũ bị từ chối), kiểm tra issuer và hạn dùng.
  core không còn `JwtEncoder`: nó không phát được token. Header có `kid` để sau này đổi khoá mà không phải sửa core.
- **Claim `organizerId`** trong token của tài khoản ORGANIZER. `AuthUser` có thêm `organizerId`; core không cần hỏi
  identity "người này thuộc ban tổ chức nào".
- **Tra email gọi `POST /internal/users/lookup`** của identity (email trong body để không lọt vào log truy cập), khoá
  `X-Internal-Api-Key` riêng của core (`INTERNAL_API_KEY_CORE`). notification-service lấy email người nhận từ
  `GET /internal/users/{id}` của identity (trước đây của core), vẫn bằng khoá của nó.
- **Gọi identity ngoài transaction.** Chuyển nhượng vé tách thành `TicketTransferService` (kiểm tra quyền sở hữu,
  tra email; không transaction) và `TicketTransferSteps` (ghi dữ liệu + outbox; một transaction), theo mẫu
  `PaymentInitiation`/`PaymentInitiationSteps`. Phân công soát vé: kiểm tra quyền, tra email, rồi một câu INSERT
  tự commit. identity không trả lời → `502 IDENTITY_UNAVAILABLE`, không đổi dữ liệu.
- **Dữ liệu mẫu dùng id cố định** (`contracts.md`, mục 4): identity tạo tài khoản mẫu, core tạo sự kiện mẫu cho đúng
  các id đó mà không cần gọi identity lúc khởi động, nên hai service bật theo thứ tự nào cũng được.

## Đánh đổi
- **Mất kiểm tra toàn vẹn ở database** cho id người dùng trong core: một `user_id` không tồn tại không bị database
  chặn nữa. Chấp nhận được vì id chỉ đến từ JWT đã ký hoặc từ identity; không có API nào cho khách tự gõ id người khác.
- **Người dùng bị xoá/khoá vẫn dùng được token cũ tới khi hết hạn (1 giờ).** Đây là bản chất của JWT tự kiểm tra;
  muốn chặn ngay thì cần token ngắn hạn + refresh token, hoặc danh sách thu hồi. Chưa làm.
- **core phụ thuộc identity lúc chạy ở hai chỗ**: lấy JWKS (một lần rồi giữ trong bộ nhớ) và tra email (chuyển
  nhượng, phân công). Đặt vé, thanh toán, check-in không gọi identity. Nếu core vừa khởi động mà identity tắt, mọi API
  cần đăng nhập trả `502 IDENTITY_UNAVAILABLE` tới khi identity sống lại. Mặc định Spring Security trả 500 ở tình
  huống này (lỗi lấy JWKS được ném ra ngoài chuỗi filter); `TokenVerificationUnavailableFilter` đổi nó thành 502
  ProblemDetail. Tìm ra khi chạy thử bằng tay, có test `JwksUnavailableIT` (đỏ khi bỏ filter).
- **Client gọi hai địa chỉ**: đăng nhập ở `:8082`, còn lại ở `:8080`. api-gateway (bước 3) sẽ gộp về một cổng.
- Test của core không còn tạo user trong database: `FakeIdentity` (HTTP server giả) phục vụ JWKS và tra email,
  `TestData.token` ký bằng khoá RSA sinh lúc chạy test. Test acceptance giữ nguyên.

## Bằng chứng
- core-service `./mvnw verify`: 48 unit + 122 integration test xanh; thư mục `acceptance/` không đổi so với bước 1.
  Test mới: `JwtVerificationIT` (token ký bằng khoá lạ, HS256, sai issuer → 401; ORGANIZER thiếu claim → 403),
  `IdentityOutageIT` (identity sập → 502 và không đổi dữ liệu; người không giữ vé nhận 404 mà core không hề tra email).
- notification-service `./mvnw verify`: 13 test xanh, có ca identity sập rồi sống lại.
- identity-service `./mvnw verify`: 4 unit + 23 integration test xanh (`JwtAndJwksIT` kiểm tra token chỉ bằng JWKS).
- Chạy cả hệ thống bằng `infra/scripts/demo.sh` (2026-10-16): đăng ký và đăng nhập ở identity, đặt vé ở core, email
  có 2 QR, check-in OK. Chuyển nhượng vé gửi email cho cả hai. Tắt identity: token cũ vẫn dùng được ở core, chuyển
  nhượng trả 502 và vé không đổi chủ.

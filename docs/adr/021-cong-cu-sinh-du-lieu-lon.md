# ADR-021: Công cụ sinh dữ liệu lớn: mỗi service sinh phần của mình, khớp nhau bằng id tất định

- Trạng thái: Đã chấp nhận
- Ngày: 2026-10-21
- Liên quan: ADR-012 (database riêng mỗi service), ADR-013 (tài khoản ở identity), ADR-016…020 (M4, core-service)

## Bối cảnh
M4 của lộ trình bắt đầu bằng "viết công cụ sinh dữ liệu giả đủ lớn để thấy được vấn đề": hệ thống đã chạy 2 năm, 2
triệu user, 10 triệu đơn, 30 triệu dòng log check-in. Với vài chục dòng, mọi truy vấn đều nhanh và không đo được gì.

Sau khi tách microservice, dữ liệu một đơn nằm ở hai nơi: tài khoản người mua ở database `identity`, đơn và vé ở
database `core`. Service không được đọc hay ghi database của service khác (ADR-012).

## Các phương án
1. **Gọi API thật** (đăng ký, đặt vé, thanh toán qua MockPay) hàng triệu lần. Đi qua đúng nghiệp vụ, nhưng 10 triệu
   đơn là hàng chục giờ, và nhiều thứ cần (đơn của 2 năm trước, check-in đã diễn ra) không tạo được qua API vì đồng hồ.
2. **Một script SQL** ghi thẳng vào cả hai database. Nhanh, nhưng phá ADR-012: một chỗ biết cấu trúc bảng của mọi
   service.
3. **Mỗi service một công cụ sinh** cho database của mình (profile `datagen`), hai bên tính id theo cùng công thức tất
   định, nên đơn của core trỏ đúng tài khoản identity đã sinh mà không bên nào đọc database của bên kia.

## Quyết định
Chọn phương án 3.

- identity-service `dev/DataGenerator`: ban tổ chức, tài khoản ORGANIZER, nhân viên soát vé, 2 triệu khách đăng ký dần
  trong 2 năm. core-service `dev/datagen/CoreDataGenerator`: địa điểm, 2.000 sự kiện rải từ 2 năm trước tới 3 tháng
  sau, loại vé, ghế, 10 triệu đơn (90% đã giao vé, còn lại hết hạn hoặc huỷ; một nửa đổ vào 2 giờ đầu mở bán), thanh
  toán, vé, 30 triệu lượt quét. Một sự kiện lớn đang mở bán 200.000 đơn thuộc ban tổ chức mẫu Sky, để xem trên web.
- Công thức id (`DatagenIds` ở cả hai repo) là hợp đồng, ghi ở `contracts.md` mục 6 và giữ bằng test hai bên.
  Id nội bộ của core (đơn, vé...) cũng tất định (UUID version 8 từ số thứ tự sự kiện và số thứ tự trong sự kiện):
  64 bit thấp gói (loại, sự kiện, số thứ tự) nên không trùng; 4 ký tự đầu cố định theo sự kiện, 4 ký tự sau ngẫu
  nhiên. Đã thử hai cách khác: id tăng dần thì nhanh nhưng 8 ký tự đầu (web dùng làm mã đơn, mã vé) giống nhau ở mọi
  đơn; id hoàn toàn ngẫu nhiên thì mỗi INSERT rơi vào một chỗ ngẫu nhiên của index khoá chính, bảng 10 triệu dòng
  không nằm vừa bộ nhớ đệm, sinh chậm đi khoảng 4 lần (600 sự kiện 615 giây, so với 1.000 sự kiện 245 giây). Đó cũng
  là chi phí thật của `UUID.randomUUID()` trên bảng rất lớn, và là lý do UUID version 7 (có thời gian ở đầu) ra đời.
- Đơn thứ k của sự kiện e tính hoàn toàn từ (seed, e, k), nên công cụ đi qua danh sách đơn nhiều lượt, mỗi lượt ghi
  một bảng theo thứ tự khoá ngoại (orders → seats → order_items → payments → tickets → checkin_logs), mà không giữ
  200.000 đơn trong bộ nhớ.
- Ghi bằng `COPY ... FROM STDIN` (API riêng của driver PostgreSQL: driver chuyển từ phạm vi `runtime` sang `compile`,
  không thêm dependency), mỗi sự kiện một transaction, 4 luồng song song, `synchronous_commit = off` trong transaction.
  Không đi qua nghiệp vụ, nên các bảng suy ra được từ bảng gốc (tồn kho GA, ghế đã bán, bảng tổng hợp doanh thu, hạn
  mức mua của sự kiện còn mở bán) được tính từ kế hoạch hoặc bằng SQL sau cùng, cho khớp tuyệt đối. `CoreDataGeneratorIT`
  chạy bộ kiểm tra bất biến của M2 (`Invariants`) trên dữ liệu sinh.
- Chạy cả hệ thống: `scripts/datagen.sh` (image của profile `apps`, profile `dev,datagen` để tài khoản mẫu có trước),
  hoặc `--small`. Chạy xong app tự tắt; database đã có dữ liệu sinh thì không sinh chồng. Mọi tài khoản sinh ra dùng
  chung một hash BCrypt của `Passw0rd!` (băm 2 triệu lần mất hàng giờ).

## Hệ quả và đánh đổi
- Được: dữ liệu cỡ lộ trình trong khoảng 10 phút, đúng ranh giới service, lặp lại được (cùng seed ra cùng dữ liệu).
- Mất: dữ liệu sinh không đi qua nghiệp vụ, nên mỗi lần đổi bảng (thêm cột NOT NULL, bảng mới có khoá ngoại) phải
  sửa cả công cụ sinh (ghi trong CLAUDE.md của core). Database to thêm khoảng 25GB (core 24GB, identity 1,2GB). Hai công cụ phải chạy với cùng các
  con số `customers`, `organizers`, `staff` (script truyền một lần cho cả hai).

## Bằng chứng
- `CoreDataGeneratorIT`: quy mô nhỏ, dữ liệu thoả mọi bất biến (ghế không thuộc hai vé, tồn kho GA, hạn mức, ghế
  SOLD thuộc đơn đã trả), đơn giao vé có đủ vé, mỗi vé đã vào cổng đúng một lượt OK, bảng tổng hợp khớp bảng gốc,
  không dòng nào rơi vào bảng default của `checkin_logs`, chạy lần hai không sinh thêm.
  `DataGeneratorIT` (identity): tài khoản sinh ra đăng nhập được.

## Đo
Máy dev 20 nhân, 30GB RAM, NVMe, PostgreSQL 17 cấu hình mặc định của image (`shared_buffers` 128MB):

| Bước | Thời gian |
|---|---|
| identity: 2.000.811 tài khoản (kể cả tài khoản mẫu) | 38 giây |
| core: kế hoạch 2.000 sự kiện (15,8 triệu vé sẽ vào cổng) | 3 giây |
| core: ghi 86,4 triệu dòng (4 luồng `COPY`) | 548 giây |
| core: tính bảng tổng hợp doanh thu cho 10 triệu đơn | 28 giây |
| Cả `scripts/datagen.sh` (gồm khởi động container) | 10 phút 26 giây |

Database `core` 24GB, `identity` 1,2GB.

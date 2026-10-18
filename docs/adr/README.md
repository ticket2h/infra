# Architecture Decision Records cấp hệ thống

Quyết định ảnh hưởng tới nhiều service. ADR-001…010 (thiết kế bên trong lõi đặt vé, từ thời monolith TicketRush) nằm ở
[`core-service/docs/adr/`](https://github.com/ticket2h/core-service/tree/main/docs/adr); số thứ tự chạy tiếp từ 011 để không trùng. Không sửa ADR đã chấp nhận; quyết định thay đổi
thì viết ADR mới và đánh dấu ADR cũ là "Bị thay thế bởi ADR-NNN".

| ADR | Chủ đề |
|---|---|
| [011](011-tach-notification-service.md) | Tách notification-service, lấy dữ liệu qua API nội bộ thay vì nhét vào event |
| [012](012-nhieu-repo-database-rieng.md) | Mỗi service một repo, một database; đổi tên hệ thống thành Ticket2h |
| [013](013-tach-identity-service.md) | Tách identity-service; core tin JWT RS256 qua JWKS, không giữ bản sao người dùng |
| [014](014-repo-tu-dung-ci-image.md) | Mỗi repo tự đứng được: CI riêng, image trên GHCR, infra chạy cả hệ thống từ image |
| [015](015-web-gateway-refresh-token.md) | Web SPA, gateway nginx trong image web-app, refresh token cookie, OpenAPI |

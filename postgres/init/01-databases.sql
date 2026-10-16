-- Database-per-service: mỗi service một user và một database riêng, chỉ chủ database được kết nối.
-- service này không đọc được bảng của service khác; muốn dữ liệu của nhau thì
-- gọi API hoặc nghe event (infra/docs/contracts.md).
-- File này chỉ chạy khi volume pgdata còn trống. Thêm service mới vào máy đã có dữ liệu thì chạy tay:
--   docker compose exec -T postgres psql -U postgres < postgres/init/01-databases.sql   (bỏ các dòng đã có)
-- Mật khẩu chỉ dùng cho máy local.

CREATE USER core WITH PASSWORD 'core';
CREATE DATABASE core OWNER core;
REVOKE CONNECT ON DATABASE core FROM PUBLIC;

CREATE USER notification WITH PASSWORD 'notification';
CREATE DATABASE notification OWNER notification;
REVOKE CONNECT ON DATABASE notification FROM PUBLIC;

CREATE USER identity WITH PASSWORD 'identity';
CREATE DATABASE identity OWNER identity;
REVOKE CONNECT ON DATABASE identity FROM PUBLIC;

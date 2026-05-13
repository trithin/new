# Telegram Bot Bán Tài Khoản + Web Admin (Dart)

## Giới thiệu
Dự án cung cấp hệ thống bán tài khoản tự động gồm:
- Telegram Bot để người dùng nạp tiền, mua tài khoản, xem số dư và lịch sử mua.
- Web Admin Panel để quản lý danh mục, tài khoản, người dùng và thống kê.

Công nghệ chính:
- Dart (bot + backend API)
- SQLite (`sqlite3`)
- `shelf` + `shelf_router` + `shelf_static`
- HTML/CSS/JS thuần cho admin panel

## Tính năng

### Telegram Bot
- `/start`: đăng ký user và hiển thị menu chính
- `💰 Số dư`: xem số dư hiện tại
- `💳 Nạp tiền`: xem hướng dẫn chuyển khoản, nội dung `NAP_[telegram_id]`
- `🛒 Mua tài khoản`: chọn danh mục, xem giá/tồn, xác nhận mua
- `📋 Lịch sử mua`: xem 10 giao dịch gần nhất
- Admin commands:
  - `/addbalance [user_id] [amount]`
  - `/stats`

### Web Admin Panel
- Login nhận JWT qua API
- Dashboard: tổng user, doanh thu, tồn kho, đã bán + giao dịch gần đây
- Quản lý danh mục: thêm/sửa/xóa/bật tắt
- Quản lý tài khoản: lọc theo danh mục/trạng thái, thêm lẻ, thêm hàng loạt, xóa tài khoản chưa bán
- Quản lý người dùng: tìm kiếm, cộng số dư

## Cấu trúc dự án

```
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── config.dart
│   ├── database/database.dart
│   ├── models/
│   ├── bot/
│   └── server/
└── web/
    ├── index.html
    ├── dashboard.html
    ├── accounts.html
    ├── categories.html
    ├── users.html
    ├── css/style.css
    └── js/*.js
```

## Cài đặt & chạy

1. Cài Dart SDK (>=3.0.0 <4.0.0)
2. Cài dependencies:
   ```bash
   dart pub get
   ```
3. Chạy ứng dụng:
   ```bash
   dart run lib/main.dart \
     --define=BOT_TOKEN=<bot_token> \
     --define=ADMIN_ID=<telegram_admin_id> \
     --define=ADMIN_USERNAME=admin \
     --define=ADMIN_PASSWORD=admin123 \
     --define=JWT_SECRET=your_secret
   ```

Ứng dụng sẽ chạy bot và server song song bằng `Future.wait([runBot(), runServer()])`.

## Cấu hình biến môi trường
Các biến cấu hình tại `lib/config.dart`:
- `BOT_TOKEN`
- `ADMIN_ID`
- `ADMIN_USERNAME`
- `ADMIN_PASSWORD`
- `JWT_SECRET`
- `serverPort` mặc định `8080`
- Thông tin ngân hàng nạp tiền: `bankName`, `bankAccount`, `bankOwner`

## Cách sử dụng bot
1. Người dùng gõ `/start`
2. Chọn menu:
   - `💰 Số dư`
   - `🛒 Mua tài khoản`
   - `💳 Nạp tiền`
   - `📋 Lịch sử mua`
3. Nạp tiền bằng chuyển khoản với nội dung `NAP_[telegram_id]`
4. Admin xác nhận nạp qua lệnh `/addbalance [user_id] [amount]`

## Truy cập Admin Panel
- URL: `http://localhost:8080/`
- Đăng nhập tại `index.html`
- Sau login thành công, token JWT lưu vào `localStorage`
- Các API `/api/*` (trừ `/api/auth/login`) yêu cầu header:
  `Authorization: Bearer <token>`

## API chính
- `POST /api/auth/login`
- `GET/POST/PUT/DELETE /api/categories`
- `GET/POST /api/accounts`, `POST /api/accounts/bulk`, `DELETE /api/accounts/:id`
- `GET /api/users`, `POST /api/users/:id/add-balance`
- `GET /api/stats`

## Ghi chú dữ liệu khởi tạo
Khi DB rỗng, hệ thống tự seed 4 danh mục mẫu:
- 🟢 Tài khoản thường – 10,000 VNĐ
- ⭐ Tài khoản Pro – 50,000 VNĐ
- 🌐 Tài khoản Web A – 30,000 VNĐ
- 🌐 Tài khoản Web B – 35,000 VNĐ

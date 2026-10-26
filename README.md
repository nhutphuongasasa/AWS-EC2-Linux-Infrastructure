# Linux Server Hardening & Operations Lab

Dự án thực hành ghi lại toàn bộ quá trình xây dựng một máy chủ Linux trên AWS EC2 từ đầu — từ bước hardening bảo mật, triển khai ứng dụng web bằng Docker, đến xây dựng hệ thống vận hành tự động (backup, giám sát, phục hồi dữ liệu).

---

## Mục lục

- [Tổng quan](#tổng-quan)
- [Cấu trúc thư mục](#cấu-trúc-thư-mục)
- [Công nghệ sử dụng](#công-nghệ-sử-dụng)
- [Kiến trúc hệ thống](#kiến-trúc-hệ-thống)
- [Hướng dẫn triển khai](#hướng-dẫn-triển-khai)
- [Docker Stack](#docker-stack)
- [Giám sát và tự động hóa](#giám-sát-và-tự-động-hóa)
- [Backup và phục hồi](#backup-và-phục-hồi)
- [Tham chiếu cấu hình](#tham-chiếu-cấu-hình)

---

## Tổng quan

Dự án này tập trung vào 3 mảng chính:

1. **Hardening máy chủ** — Bảo mật một EC2 Ubuntu mặc định bằng UFW, Fail2Ban, SSH hardening và kiểm tra bảo mật với Lynis.
2. **Triển khai ứng dụng web bằng Docker** — Stack Nginx + PHP-FPM + MariaDB chạy trên Docker Compose, có áp dụng các biện pháp bảo mật ở cấp độ container.
3. **Tự động hóa vận hành** — Backup tự động, health check và giám sát disk thông qua các script Bash được kích hoạt bởi Systemd timer.

---

## Cấu trúc thư mục

```
.
├── config/
│   └── lab-web-monitor.conf        # File cấu hình chung cho các script giám sát
│
├── docker/
│   ├── docker-compose.yml          # Định nghĩa toàn bộ Docker stack
│   ├── nginx/
│   │   └── default.conf            # Cấu hình virtual host Nginx
│   ├── php/
│   │   └── Dockerfile              # Image PHP 8.3-FPM với extension mysqli
│   └── mariadb/
│       └── custom.cnf              # Cấu hình tùy chỉnh MariaDB
│
├── scripts/
│   ├── backup.sh                   # Backup source code và database
│   ├── server_healthcheck.sh       # Kiểm tra disk, Docker service và HTTP
│   ├── disk_monitor.sh             # Giám sát dung lượng disk theo ngưỡng cảnh báo
│   └── recovery.sh                 # Phục hồi database từ file backup
│
├── systemd/
│   ├── backup.service / .timer             # Chạy backup mỗi ngày lúc 02:00
│   ├── server-healthcheck.service / .timer # Chạy health check mỗi 5 phút
│   └── disk-monitor.service / .timer       # Chạy giám sát disk mỗi 15 phút
│
└── docs/
    └── images/                     # Ảnh chụp màn hình và bằng chứng thực hiện
```

---

## Công nghệ sử dụng

| Thành phần | Công nghệ |
|---|---|
| Cloud | AWS EC2 (Ubuntu) |
| Web server | Nginx 1.27 Alpine |
| Môi trường chạy ứng dụng | PHP 8.3-FPM Alpine |
| Cơ sở dữ liệu | MariaDB 11.4 |
| Container hóa | Docker Compose |
| Tự động hóa | Bash + Systemd timer |
| Công cụ bảo mật | UFW, Fail2Ban, Lynis |

---

## Kiến trúc hệ thống

```
Internet
    |
    v
[ AWS Security Group ]  -- Cho phép cổng: 22 (SSH), 80 (HTTP)
    |
    v
[ EC2 Instance ]
    |
    |-- UFW Firewall
    |-- Fail2Ban (bảo vệ SSH khỏi brute-force)
    |
    v
[ Docker Compose ]
    |
    |-- nginx  (mạng frontend)          -- Lắng nghe cổng 80, expose ra host
    |       |
    |       |-- fastcgi_pass --> php:9000
    |
    |-- php    (mạng frontend + backend)
    |       |
    |       |-- kết nối --> mariadb:3306
    |
    |-- mariadb (mạng backend, nội bộ)  -- KHÔNG expose cổng ra host
            |
            |-- dữ liệu lưu tại /srv/data/mariadb (bind mount trên host)
```

**Phân tách mạng:**
- Mạng `frontend`: Nginx và PHP giao tiếp với nhau.
- Mạng `backend`: Chỉ có PHP và MariaDB. MariaDB không được expose cổng ra ngoài host, tránh truy cập trực tiếp từ bên ngoài.

![Trạng thái Docker containers](docs/images/docker_state.png)

---

## Hướng dẫn triển khai

### Yêu cầu

- EC2 Ubuntu 22.04
- Đã cài Docker và Docker Compose v2
- AWS Security Group đã mở cổng 80

### Bước 1 — Clone repository

```bash
git clone <repo-url> ~/lab-web
cd ~/lab-web
```

### Bước 2 — Tạo file biến môi trường

```bash
cp .env.example .env
nano .env
```

Điền các giá trị cần thiết:

```env
DB_ROOT_PASSWORD=mat_khau_root
DB_DATABASE=labdb
DB_USER=labuser
DB_PASSWORD=mat_khau_user
```

### Bước 3 — Khởi động Docker stack

```bash
docker compose -f docker/docker-compose.yml up -d
```

Kiểm tra các container đang chạy:

```bash
docker compose -f docker/docker-compose.yml ps
```

### Bước 4 — Cài đặt các script giám sát

```bash
sudo cp scripts/backup.sh               /usr/local/backup.sh
sudo cp scripts/server_healthcheck.sh   /usr/local/server_healthcheck.sh
sudo cp scripts/disk_monitor.sh         /usr/local/disk_monitor.sh
sudo chmod +x /usr/local/backup.sh /usr/local/server_healthcheck.sh /usr/local/disk_monitor.sh
```

### Bước 5 — Cài đặt file cấu hình giám sát

```bash
sudo cp config/lab-web-monitor.conf /etc/lab-web-monitor.conf
sudo nano /etc/lab-web-monitor.conf   # chỉnh lại đường dẫn cho phù hợp
```

### Bước 6 — Cài đặt và kích hoạt Systemd timer

```bash
sudo cp systemd/*.service systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer
sudo systemctl enable --now server-healthcheck.timer
sudo systemctl enable --now disk-monitor.timer
```

---

## Docker Stack

### Nginx (`docker/nginx/default.conf`)

Phục vụ file tĩnh và chuyển tiếp các request `.php` sang PHP-FPM qua FastCGI. Các security header được gắn vào tất cả response:

| Header | Giá trị | Mục đích |
|---|---|---|
| `X-Frame-Options` | `SAMEORIGIN` | Chống clickjacking |
| `X-Content-Type-Options` | `nosniff` | Chống MIME sniffing |
| `Content-Security-Policy` | `default-src 'self'` | Chặn tải tài nguyên ngoài |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Kiểm soát thông tin referrer |
| `Permissions-Policy` | geolocation, microphone, camera tắt hết | Tắt các API nhạy cảm |

Các dotfile như `.env`, `.git` bị chặn hoàn toàn bằng `deny all`.

![Trạng thái UFW firewall](docs/images/ufw.png)

![Fail2Ban đang hoạt động](docs/images/fail2ban.png)

`server_tokens off` được bật để ẩn phiên bản Nginx khỏi response header.

### PHP (`docker/php/Dockerfile`)

```dockerfile
FROM php:8.3-fpm-alpine
RUN docker-php-ext-install mysqli
USER www-data
```

Container chạy với user `www-data` (không phải root). Chỉ cài extension `mysqli` — không cài thêm bất kỳ thứ gì không cần thiết.

### MariaDB (`docker/mariadb/custom.cnf`)

```ini
[mysqld]
skip-name-resolve     # Bỏ qua DNS lookup khi có kết nối vào — tăng tốc trong môi trường Docker
bind-address = 0.0.0.0  # Cho phép kết nối từ các container khác trong cùng mạng Docker
```

Cổng 3306 **không được expose ra host**. MariaDB chỉ tiếp nhận kết nối từ container PHP qua mạng nội bộ `backend`.

Dữ liệu được lưu tại `/srv/data/mariadb` trên host (bind mount), đảm bảo dữ liệu không bị mất khi chạy `docker compose down`.

![Thông tin disk và phân vùng (lsblk)](docs/images/show_lsblk_before.png)

### Giới hạn tài nguyên container

| Container | Giới hạn CPU | Giới hạn RAM |
|---|---|---|
| nginx | 0.5 core | 256 MB |
| php | 0.5 core | 256 MB |
| mariadb | 1.0 core | 512 MB |

---

## Giám sát và tự động hóa

Tất cả script giám sát đều đọc cấu hình từ `/etc/lab-web-monitor.conf`.

### File cấu hình (`lab-web-monitor.conf`)

```bash
PROJECT_DIR="/home/phuong/lab-web"       # Thư mục gốc của dự án trên host
COMPOSE_FILE="/home/phuong/lab-web/docker-compose.yml"
HTTP_URL="http://localhost"              # URL dùng để kiểm tra HTTP
DISK_WARN=80                            # Cảnh báo khi disk dùng >= 80%
DISK_CRIT=90                            # Báo lỗi nghiêm trọng khi disk dùng >= 90%
```

### server_healthcheck.sh

Chạy mỗi **5 phút** (lần đầu sau 2 phút kể từ khi boot).

Kiểm tra:
- Dung lượng RAM hiện tại (ghi log qua `free -h`)
- Dung lượng disk tại `PROJECT_DIR` theo ngưỡng `DISK_WARN` và `DISK_CRIT`
- Tất cả service trong Docker Compose có đang chạy không
- HTTP endpoint (`HTTP_URL`) có trả về mã `2xx` không

Ghi log tại: `/var/log/lab-web/server-healthcheck.log`

Mã thoát: `0` = bình thường, `1` = có cảnh báo, `2` = có lỗi nghiêm trọng.

![Server healthcheck chạy thực tế](docs/images/server_healthcheck.png)

### disk_monitor.sh

Chạy mỗi **15 phút** (lần đầu sau 3 phút kể từ khi boot).

Kiểm tra tất cả filesystem đang mount, bỏ qua `tmpfs`, `devtmpfs`, `overlay`, `squashfs`.

Có thể ghi đè ngưỡng cảnh báo tạm thời mà không cần sửa file config:

```bash
DISK_WARN_OVERRIDE=70 DISK_CRIT_OVERRIDE=85 ./scripts/disk_monitor.sh
```

Ghi log tại: `/home/phuong/lab-web/logs/disk-monitor.log`

### Lịch chạy Systemd timer

| Timer | Lịch chạy |
|---|---|
| `backup.timer` | Mỗi ngày lúc 02:00 |
| `server-healthcheck.timer` | Mỗi 5 phút |
| `disk-monitor.timer` | Mỗi 15 phút |

Kiểm tra trạng thái timer:

```bash
systemctl list-timers
journalctl -u server-healthcheck.service -f
journalctl -u disk-monitor.service -f
journalctl -u backup.service -f
```

---

## Backup và phục hồi

### backup.sh

Chạy tự động mỗi ngày lúc 02:00 qua `backup.timer`.

Mỗi lần chạy tạo ra 2 file:

![Backup đang chạy](docs/images/backup.png)

| File | Nội dung |
|---|---|
| `src-YYYYMMDD-HHMMSS.tar.gz` | Source code + cấu hình Nginx, PHP, MariaDB và `docker-compose.yml` |
| `db-YYYYMMDD-HHMMSS.sql.gz` | Toàn bộ database dump (single-transaction, bao gồm routines và triggers) |

File backup lưu tại `/srv/data/backups/lab-web`. Các file cũ hơn ngưỡng retention sẽ bị xóa tự động.

File dump database được kiểm tra tính toàn vẹn bằng `gzip -t` trước khi được đặt tên chính thức — nếu dump bị lỗi, file `.tmp` sẽ không được đổi tên và lần chạy đó thất bại rõ ràng.

### recovery.sh

Phục hồi database từ một file backup. Yêu cầu xác nhận thủ công trước khi thực hiện.

```bash
sudo ./scripts/recovery.sh db-20241025-020001.sql.gz
```

Script thực hiện theo thứ tự:

![Xóa bảng để demo recovery](docs/images/drop_table.png)

![Chạy recovery](docs/images/recovery_exec.png)

![Database sau khi phục hồi](docs/images/recovery_database.png)

1. Kiểm tra file backup tồn tại và là file gzip hợp lệ.
2. Đọc thông tin đăng nhập database từ file `.env` của dự án.
3. Hiển thị thông tin backup và yêu cầu gõ `RESTORE` để xác nhận.
4. Giải nén và pipe SQL trực tiếp vào container MariaDB đang chạy.

---

## Tham chiếu cấu hình

### `/etc/lab-web-monitor.conf`

| Biến | Mô tả | Ví dụ |
|---|---|---|
| `PROJECT_DIR` | Đường dẫn thư mục gốc dự án trên host | `/home/phuong/lab-web` |
| `COMPOSE_FILE` | Đường dẫn tới file `docker-compose.yml` | `/home/phuong/lab-web/docker-compose.yml` |
| `HTTP_URL` | URL dùng để kiểm tra HTTP health check | `http://localhost` |
| `DISK_WARN` | Ngưỡng phần trăm disk để cảnh báo | `80` |
| `DISK_CRIT` | Ngưỡng phần trăm disk để báo lỗi nghiêm trọng | `90` |

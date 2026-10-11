# Bài 5: Nối Job tự động Build & Push Docker Image sau khi Test Gradle xanh

## Mục tiêu

- Tách luồng CI thành **2 Job riêng biệt**: `test` (Gradle test + build JAR) và `docker-build` (đóng gói Docker Image).
- Dùng từ khóa `needs` để ràng buộc thứ tự: `docker-build` chỉ chạy khi `test` thành công.

---

## Cấu trúc thư mục

```
ex5/
├── .github/
│   └── workflows/
│       └── ci.yml              ← File workflow CI chính (2 jobs)
├── gradle/wrapper/
│   └── gradle-wrapper.properties
├── src/
│   ├── main/java/com/example/demo/
│   │   └── DemoApplication.java
│   ├── main/resources/
│   │   └── application.properties
│   └── test/java/com/example/demo/
│       └── DemoApplicationTests.java
├── .dockerignore
├── build.gradle
├── Dockerfile
├── gradlew
├── gradlew.bat
└── settings.gradle
```

---

## Sơ đồ luồng Workflow

```
┌─────────────────────────────────┐
│  Job: test                      │
│  ─────────────────────────────  │
│  1. Checkout mã nguồn           │
│  2. Setup Java 17               │
│  3. chmod +x gradlew            │
│  4. ./gradlew test              │  ── Nếu FAIL → docker-build bị SKIP
│  5. ./gradlew bootJar           │
│  6. Upload artifact JAR         │
└────────────────┬────────────────┘
                 │  needs: test (chỉ tiếp tục nếu ✅ xanh)
                 ▼
┌─────────────────────────────────┐
│  Job: docker-build              │
│  ─────────────────────────────  │
│  1. Checkout mã nguồn           │
│  2. Download artifact JAR       │
│  3. docker/login-action@v3      │
│  4. docker/setup-buildx-action  │
│  5. docker/metadata-action      │
│  6. docker/build-push-action@v5 │ ── Push lên ghcr.io
└─────────────────────────────────┘
```

---

## Hướng dẫn thực hiện

### Bước 1 — Đảm bảo Secret đã có (từ Bài 4)

Repository cần có secret `REGISTRY_TOKEN` với quyền `write:packages`.  
Xem hướng dẫn tạo token tại [README bài 4](../ex4/README.md).

### Bước 2 — Đẩy code lên GitHub

```bash
git add .
git commit -m "feat: add 2-job CI workflow with docker build-push (ex5)"
git push origin main
```

### Bước 3 — Kiểm tra sơ đồ Job

1. Vào tab **Actions** → chọn workflow run mới nhất.
2. Giao diện hiển thị **biểu đồ 2 job** với mũi tên nối từ `test` → `docker-build`.
3. Xác nhận cả 2 job đều có trạng thái ✅ **Success**.

> **Ảnh chụp màn hình cần nộp:** Biểu đồ workflow hiển thị sơ đồ 2 job kết nối thành công.

### Bước 4 — Kiểm tra trường hợp Test thất bại

Để xác minh cơ chế `needs` hoạt động đúng:

1. Sửa file test để JUnit thất bại, ví dụ thêm vào `DemoApplicationTests.java`:
   ```java
   @Test
   void failingTest() {
       // Cố tình làm test thất bại
       org.junit.jupiter.api.Assertions.fail("Test bị hỏng!");
   }
   ```
2. Đẩy code lên GitHub.
3. Quan sát tab Actions: Job `test` ❌ **Failed** → Job `docker-build` ⏭️ **Skipped**.

---

## Nội dung file ci.yml

```yaml
name: CI - Bài 5 Build và Push Docker Image lên GHCR

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  test:
    name: Gradle Test & Build JAR
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - run: chmod +x gradlew
      - run: ./gradlew test
      - run: ./gradlew bootJar
      - uses: actions/upload-artifact@v4
        with:
          name: app-jar
          path: build/libs/*.jar

  docker-build:
    name: Build and Push Docker Image
    needs: test                          # ← Ràng buộc thứ tự
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: app-jar
          path: build/libs/
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.REGISTRY_TOKEN }}
      - uses: docker/setup-buildx-action@v3
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
      - uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

---

## Giải thích các thành phần chính

| Thành phần | Ý nghĩa |
|---|---|
| `needs: test` | Job `docker-build` chỉ chạy khi `test` hoàn thành thành công |
| `upload-artifact` / `download-artifact` | Truyền file JAR từ job `test` sang job `docker-build` |
| `docker/metadata-action@v5` | Tự động tạo tags (`latest`, `sha-xxxxx`, tên branch) |
| `docker/build-push-action@v5` | Build Dockerfile và push image lên GHCR |
| `push: ${{ github.event_name != 'pull_request' }}` | Chỉ push image khi là commit trực tiếp, không push khi PR |
| `cache-from/cache-to: type=gha` | Cache Docker layer trên GitHub Actions để tăng tốc build |

---

## Image được push lên GHCR

Sau khi workflow chạy thành công, image có thể được pull về:

```bash
docker pull ghcr.io/<your-github-username>/<repo-name>:latest
```

---

## Sản phẩm nộp bài

- [x] File `.github/workflows/ci.yml` gồm 2 job liên kết qua `needs: test`
- [ ] Ảnh chụp màn hình **biểu đồ workflow** hiển thị sơ đồ 2 job kết nối thành công
- [ ] Ảnh chụp màn hình job `docker-build` ở trạng thái **Skipped** khi test thất bại

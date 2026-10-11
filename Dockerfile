# ─── Stage 1: Build ───────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jdk-alpine AS builder

WORKDIR /app

# Copy Gradle wrapper và cấu hình trước để tận dụng Docker layer cache
COPY gradlew .
COPY gradle gradle
COPY build.gradle .
COPY settings.gradle .

# Cấp quyền thực thi
RUN chmod +x gradlew

# Tải dependencies (layer riêng, cache khi chỉ thay đổi source code)
RUN ./gradlew dependencies --no-daemon

# Copy toàn bộ mã nguồn và đóng gói JAR
COPY src src
RUN ./gradlew bootJar --no-daemon

# ─── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Tạo user non-root để bảo mật
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy JAR từ stage build
COPY --from=builder /app/build/libs/*.jar app.jar

# Chuyển sang user non-root
USER appuser

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]

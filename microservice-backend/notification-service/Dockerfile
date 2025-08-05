# -------- STAGE 1: Build with Maven --------
FROM maven:3.9.5-eclipse-temurin-17 AS builder
WORKDIR /app

COPY . .

RUN mvn clean package -DskipTests

# -------- STAGE 2: Minimal runtime image --------
FROM eclipse-temurin:17-jdk-alpine

WORKDIR /app

COPY --from=builder /app/target/*.jar app.jar


ENTRYPOINT ["java", "-jar", "app.jar"]

FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
# Tests run in CI before this packaging stage.
RUN mvn -B package -DskipTests

FROM eclipse-temurin:21-jre-jammy
# Patch Ubuntu packages flagged in the initial image scan.
RUN apt-get update \
    && apt-get install -y --no-install-recommends --only-upgrade apt libapt-pkg6.0 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build --chown=10001:10001 /build/target/*.jar /app/app.jar
USER 10001:10001
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=70 -Djava.io.tmpdir=/tmp"
EXPOSE 9013
ENTRYPOINT ["java","-jar","/app/app.jar"]

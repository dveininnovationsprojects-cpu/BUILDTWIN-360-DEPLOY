# ---- Build stage ----
FROM eclipse-temurin:21-jdk AS build
WORKDIR /workspace

# Resolve dependencies first so this layer is cached until pom.xml changes
COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw -B -ntp dependency:go-offline

COPY src src
# Tests already run in the Jenkins Test stage
RUN ./mvnw -B -ntp package -DskipTests

# ---- Runtime stage ----
FROM eclipse-temurin:21-jre
WORKDIR /app

RUN useradd --system --no-create-home appuser
COPY --from=build /workspace/target/*.jar app.jar
USER appuser

EXPOSE 8080
# Configuration comes from environment variables, e.g.
# SPRING_DATASOURCE_URL, SPRING_DATASOURCE_USERNAME, SPRING_DATASOURCE_PASSWORD, JWT_SECRET_KEY
ENTRYPOINT ["java", "-jar", "app.jar"]

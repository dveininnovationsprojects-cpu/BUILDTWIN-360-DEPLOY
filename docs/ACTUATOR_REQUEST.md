# Request for the backend developer: health endpoint

The specification (section 15, Availability; section 12, Observability) requires service health endpoints.
The backend `pom.xml` does not include Spring Boot Actuator yet.

## What to add (backend repo, `BUILDTWIN-360-BACKEND`)

1. `pom.xml` dependency:

   ```xml
   <dependency>
       <groupId>org.springframework.boot</groupId>
       <artifactId>spring-boot-starter-actuator</artifactId>
   </dependency>
   ```

2. `application.properties`: expose only the health endpoint and hide details from anonymous callers:

   ```properties
   management.endpoints.web.exposure.include=health
   management.endpoint.health.show-details=never
   ```

3. `SecurityConfig`: allow anonymous access to `GET /actuator/health` (the API otherwise answers 401).

4. Test: `GET /actuator/health` returns `{"status":"UP"}` with HTTP 200 without a token.

## What DevOps changes afterwards

- Smoke test: replace the Swagger `/v3/api-docs` wait with `/actuator/health`.
- Compose: add a backend `healthcheck` so `depends_on` can wait for a healthy backend.

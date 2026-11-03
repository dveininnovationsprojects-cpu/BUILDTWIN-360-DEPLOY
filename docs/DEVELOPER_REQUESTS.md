# Fix requests for the BuildTwin 360 developers

Source: release-level regression and security testing (Phase 9) and the Jenkins staging pipeline
(build 9, 3 November 2026). Each item has a Known Technical Issues Register number (KTI).
DevOps does not change application code; please make these changes in the app repositories.
When an item is merged, tell DevOps and the pipeline (tests, Trivy, ZAP, k6) will be re-run to confirm.

Priority order: KTI-01, KTI-02, KTI-04, KTI-03, then the rest.

## Backend (`BUILDTWIN-360-BACKEND`)

### KTI-01 (High) Secrets committed in `application.properties`
- `spring.datasource.password=...` (line 7) and `jwt.secret.key=...` (line 26) are real values in git.
- Change to environment variables, with no default for the secrets:
  `spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}` and `jwt.secret.key=${JWT_SECRET_KEY}`.
  (The staging compose file already supplies both variables.)
- Rotate both values, because they are in git history. Use a new random JWT key of at least 64 characters.
- Done when: the repo contains no real password or key, and the app fails to start if they are missing.

### KTI-02 (High) Hardcoded passwords of the seeded users
- `DataInitializer.java` lines 325-334 create 10 users with fixed passwords (`Director@123`, `Pm@123`, ...).
  Only the `admin` password can be changed today (`app.seed.admin.password`).
- Read each password from a property or environment variable, or skip creating these users unless
  `app.seed.enabled=true`. Set `app.seed.enabled=false` for production.
- Done when: staging login with the old default passwords returns 401 for every seeded user.

### KTI-03 (High) Vulnerable libraries (11 critical, 33 high in the Trivy scan)
- Spring Boot 3.4.1 pulls Tomcat 10.1.34, Spring Security 6.4.2, Spring 6.2.1 and Jackson 2.18.2.
- Upgrade Spring Boot to the latest patched release in the same line (or the current supported line),
  run the 611 tests, and fix any breakage.
- Done when: the Jenkins "Image Scan (Trivy)" stage lists no critical findings for the backend image.

### KTI-04 (High) 8 endpoints return HTTP 500 on PostgreSQL
- Error: `function lower(bytea) does not exist`. It comes from JPQL such as
  `(:source IS NULL OR LOWER(p.source) = LOWER(:source))` in `ActivityProgressLogRepository`
  (progress history) and the matching queries for the stock ledger. PostgreSQL cannot infer the
  type of a null parameter.
- Fix: cast the parameter (`CAST(:source AS string)`), or build the filter with Specifications, or
  only add the condition when the value is not null.
- Add a test against PostgreSQL (Testcontainers) so H2 no longer hides this.
- Done when: the 8 endpoints return 200 on staging.

### KTI-06 Health endpoint (Actuator)
- Follow `docs/ACTUATOR_REQUEST.md`. Done when `GET /actuator/health` returns `{"status":"UP"}` without a token.

### KTI-07 (Medium) CORS allows any origin with credentials
- `SecurityConfig.java` line 107 has `"*"` in `setAllowedOriginPatterns` together with `setAllowCredentials(true)`.
- Remove `"*"`. Read the allowed origins from a property (for example `app.cors.allowed-origins`) and set
  the staging and production frontend URLs there.
- Done when: a request with `Origin: https://evil.example` gets no `Access-Control-Allow-Origin` header.

### KTI-08 (Medium) No login rate limit
- 40 wrong passwords in a row were all answered with 401.
- Add throttling on `/api/v1/auth/login`, for example 5 failures per minute per IP and username,
  then a temporary lock (HTTP 429) for 15 minutes. Bucket4j or a small filter is enough.
- Done when: the 6th wrong attempt within a minute returns 429, and a correct login after the lock period works.

### KTI-05 (Medium) Schema managed by `ddl-auto=update`
- Add Flyway or Liquibase migrations and set `ddl-auto=validate`. This is also a specification requirement.

### KTI-15 (Low) Swagger UI and `/v3/api-docs` are open
- Disable them or require login in the production profile. Note: the Jenkins smoke test uses `/v3/api-docs`
  on staging; tell DevOps before changing staging so the pipeline can use `/actuator/health` instead.

## Frontend (`BUILDTWIN-360-FRONTEND`)

- KTI-11 test coverage: follow `docs/COVERAGE_REQUEST.md`.
- KTI-12 npm vulnerabilities: upgrade `zod` to 4.6.7 or later (high, used at runtime). The two critical
  findings are in test tooling only and need vitest 5, so schedule that separately.
- KTI-16 bundle size: the main chunk is 1.57 MB. Use route-level `React.lazy` and `manualChunks`.

## Message to send

> Hi team, the Phase 9 testing and the Jenkins scans produced a list of fixes. Please see
> `DEVELOPER_REQUESTS.md` (backend: secrets, seeded passwords, Spring Boot upgrade, the 8 PostgreSQL 500s,
> CORS, login rate limit, health endpoint; frontend: tests, zod, bundle size). Start with KTI-01, 02 and 04.
> Tell me when each is merged and I'll re-run the pipeline to confirm.

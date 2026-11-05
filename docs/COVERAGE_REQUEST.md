# Request for the frontend developers: raise test coverage

**Current state (Jenkins build #8, 3 November 2026):** 4 tests in 2 files, coverage **0.42%**
(181 of 42,967 lines). This is tracked as KTI-11 in the Known Technical Issues Register.
The Jenkins job publishes the HTML report as "Frontend Coverage" on the job page, so you can see
which files have no tests.

## 1. Add a coverage threshold in `vite.config.js`

Repo: `BUILDTWIN-360-FRONTEND`. Replace the `coverage` block inside `test`:

```js
coverage: {
  provider: 'v8',
  reporter: ['text-summary', 'lcov'],
  reportsDirectory: './coverage',
  include: ['src/**/*.{js,jsx,ts,tsx}'],
  exclude: ['src/**/*.test.*', 'src/test/**', 'src/main.jsx', 'src/types/**', 'src/assets/**'],
  thresholds: { lines: 0, functions: 0, branches: 0, statements: 0 },
},
```

**The `include` line is required since the upgrade to vitest 4.** Vitest 4 only counts files that a test
loads. Without `include`, the current build reports 50% (10 of 20 lines), which hides the real figure of
about 0.4% for the whole `src` folder. Keep `include` so the number is honest.

Important: the CI build fails when coverage is below the thresholds. Today it is 0.42%, so
**do not set 20 yet**, or the pipeline goes red. Start at 0 (this only locks in the reporting), then raise
the numbers in the same pull request that brings coverage above them:

| Sprint | Threshold |
|--------|-----------|
| now    | 0         |
| +1     | 10        |
| +2     | 20        |
| +3     | 30        |
| +4     | 40, then 50 |

## 2. Write the tests (suggested order)

1. Design-system components (`src/design-system/components/*`), following `Button.test.jsx`.
2. Stores and utilities.
3. `lib/apiClient.jsx` and the services (mock the API with MSW).
4. `ProtectedRoute` and role checks.
5. One smoke test per module page (render, loading, empty and error states).
6. Authentication, projects, DPR, materials and cost flows with Testing Library.

## 3. Definition of done

- `npm run test:coverage` passes locally and in Jenkins.
- The threshold in `vite.config.js` is raised to just below the new coverage.
- KTI-11 is updated with the new percentage.

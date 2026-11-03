# Request for the frontend developers: coverage threshold

Frontend test coverage is 0.48% (KTI-11). The Jenkins job now publishes the HTML report
("Frontend Coverage" on the job page). To stop coverage from falling and to raise it step by step,
please change `coverage` in `vite.config.js` (frontend repo, `BUILDTWIN-360-FRONTEND`):

```js
coverage: {
  provider: 'v8',
  reporter: ['text-summary', 'lcov'],
  reportsDirectory: './coverage',
  include: ['src/**/*.{js,jsx,ts,tsx}'],
  exclude: ['src/**/*.test.*', 'src/test/**', 'src/main.jsx', 'src/types/**', 'src/assets/**'],
  thresholds: { lines: 20, functions: 20, branches: 20, statements: 20 },
},
```

Notes:

- `include` makes v8 count files that no test imports, so the reported figure becomes the real one
  (it may be lower than 0.48% at first).
- The build fails when coverage is below the thresholds. Merge the tests first, or start the
  thresholds at the current real value and raise them by 10 points each sprint
  (20, 30, 40, 50).
- Suggested order of tests: design-system components, stores and utils, `lib/apiClient.jsx`
  and services, `ProtectedRoute`, then one smoke test per module page.

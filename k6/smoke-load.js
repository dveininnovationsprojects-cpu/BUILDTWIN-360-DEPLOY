// BuildTwin 360 - light load test against staging (read-only requests).
// Run by the Jenkins staging pipeline inside the compose network:
//   k6 run -e BASE_URL=http://backend:8080 -e ADMIN_USER=admin -e ADMIN_PASSWORD=... smoke-load.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '20s', target: 10 },
    { duration: '40s', target: 10 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
  },
};

const BASE = __ENV.BASE_URL || 'http://backend:8080';

export function setup() {
  const res = http.post(
    `${BASE}/api/v1/auth/login`,
    JSON.stringify({ usernameOrEmail: __ENV.ADMIN_USER || 'admin', password: __ENV.ADMIN_PASSWORD }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(res, { 'login 200': (r) => r.status === 200 });
  return { token: res.json('data.accessToken') };
}

export default function (data) {
  const params = { headers: { Authorization: `Bearer ${data.token}` } };
  const res = http.get(`${BASE}/api/v1/projects`, params);
  check(res, { 'projects 200': (r) => r.status === 200 });
  sleep(1);
}

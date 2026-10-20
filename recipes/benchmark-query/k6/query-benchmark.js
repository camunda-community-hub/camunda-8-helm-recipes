// k6 query benchmark for the Camunda 8 Orchestration Cluster REST API (search and get endpoints).
//
// Open workload model: the arrival rate steps up through QUERY_STEPS (requests per second) and k6 keeps
// sending at that rate even when the server slows down, so degradation shows up as latency and errors
// instead of the load quietly backing off. Every step has a short ramp, then a hold. Only the hold
// is measured, per step, through the "step" tag.
//
// All settings come from environment variables (see recipes/benchmark-query/config.mk).
import http from 'k6/http';
import exec from 'k6/execution';
import { Rate } from 'k6/metrics';

const BASE_URL = (__ENV.QUERY_BASE_URL || 'http://camunda-zeebe-gateway:8080/orchestration').replace(/\/$/, '');
const AUTH = (__ENV.QUERY_AUTH || 'oidc').toLowerCase();
const TOKEN_URL = __ENV.TOKEN_URL || '';
const CLIENT_ID = __ENV.CLIENT_ID || '';
const CLIENT_SECRET = __ENV.CLIENT_SECRET || '';
const AUDIENCE = __ENV.TOKEN_AUDIENCE || '';
// Fetch one token in setup() and share it with every VU, instead of one token per VU. Needed when the token
// endpoint is rate limited (Camunda SaaS allows about one token request per second per source IP).
// The shared token is never renewed, so the run must be shorter than the token lifetime (24h on SaaS).
const SHARED_TOKEN = (__ENV.QUERY_SHARED_TOKEN || 'false').toLowerCase() === 'true';

const STEPS = (__ENV.QUERY_STEPS || '10,25,50,100').split(',').map((s) => Number(s.trim())).filter((n) => n > 0);
const STEP_SECONDS = Number(__ENV.QUERY_STEP_SECONDS || 120);
const RAMP_SECONDS = Number(__ENV.QUERY_RAMP_SECONDS || 10);
const P95_MS = Number(__ENV.QUERY_P95_MS || 500);
const MAX_ERROR_RATE = Number(__ENV.QUERY_MAX_ERROR_RATE || 0.01);
const PROCESS_ID = __ENV.QUERY_PROCESS_ID || '';
const DISABLED = (__ENV.QUERY_DISABLED || '').split(',').map((s) => s.trim()).filter(Boolean);
// Requests each VU sends in parallel per iteration. QUERY_STEPS stay in requests per second, so with a
// batch of N the scenario starts QUERY_STEPS / N iterations per second and needs about N times fewer VUs.
const BATCH = Math.max(1, Number(__ENV.QUERY_BATCH || 1));

const queryErrors = new Rate('query_errors');

const stages = [];
const thresholds = {};
for (const rate of STEPS) {
  const iterations = Math.ceil(rate / BATCH);
  stages.push({ duration: `${RAMP_SECONDS}s`, target: iterations });
  stages.push({ duration: `${STEP_SECONDS}s`, target: iterations });
  // abortOnFail stays off so the whole ramp runs. The summary shows which step crossed the line.
  thresholds[`http_req_duration{step:${rate}}`] = [`p(95)<${P95_MS}`];
  thresholds[`query_errors{step:${rate}}`] = [`rate<${MAX_ERROR_RATE}`];
  thresholds[`http_reqs{step:${rate}}`] = ['count>=0'];
}

export const options = {
  scenarios: {
    queries: {
      executor: 'ramping-arrival-rate',
      startRate: 1,
      timeUnit: '1s',
      preAllocatedVUs: Number(__ENV.QUERY_PREALLOCATED_VUS || 100),
      maxVUs: Number(__ENV.QUERY_MAX_VUS || 1000),
      stages,
    },
  },
  thresholds,
  batch: Math.max(20, BATCH),
  batchPerHost: BATCH,
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// Per-VU token cache. Tokens are renewed at 80% of their lifetime.
let token = null;
let tokenExpiresAt = 0;

function fetchToken() {
  const res = http.post(
    TOKEN_URL,
    { grant_type: 'client_credentials', client_id: CLIENT_ID, client_secret: CLIENT_SECRET, audience: AUDIENCE },
    { tags: { step: 'auth' } },
  );
  if (res.status !== 200) {
    throw new Error(`Token request failed with status ${res.status}: ${String(res.body).slice(0, 200)}`);
  }
  const body = res.json();
  token = body.access_token;
  tokenExpiresAt = Date.now() + (body.expires_in || 60) * 1000 * 0.8;
  return token;
}

function headers() {
  const h = { 'Content-Type': 'application/json', Accept: 'application/json' };
  if (AUTH === 'oidc') {
    h.Authorization = `Bearer ${token && Date.now() < tokenExpiresAt ? token : fetchToken()}`;
  }
  return h;
}

// A request spec: [method, url, body, params]. Built per query, sent alone or in a batch.
function search(path, body) {
  return ['POST', `${BASE_URL}${path}`, JSON.stringify(body)];
}

function get(path) {
  return ['GET', `${BASE_URL}${path}`, null];
}

const pick = (list) => list[Math.floor(Math.random() * list.length)];

// Sends specs in parallel when there is more than one. Tags and headers are added here.
function send(specs, tagsList) {
  const h = headers();
  const requests = specs.map((spec, i) => [spec[0], spec[1], spec[2], { headers: h, tags: tagsList[i] }]);
  return requests.length === 1 ? [http.request(...requests[0])] : http.batch(requests);
}

// The query mix. "weight" is the relative share of requests. "needsKeys" queries are skipped when the
// cluster has no process instances to point them at. Disable any of them with QUERY_DISABLED=name,name.
const QUERIES = [
  {
    name: 'process-instances-active',
    weight: 30,
    build: () => search('/v2/process-instances/search', {
      filter: { state: 'ACTIVE' },
      sort: [{ field: 'startDate', order: 'DESC' }],
      page: { limit: 50 },
    }),
  },
  {
    name: 'process-instances-by-definition',
    weight: 15,
    build: () => search('/v2/process-instances/search', {
      filter: PROCESS_ID ? { processDefinitionId: PROCESS_ID, state: 'COMPLETED' } : { state: 'COMPLETED' },
      sort: [{ field: 'endDate', order: 'DESC' }],
      page: { limit: 20 },
    }),
  },
  {
    name: 'process-instance-by-key',
    weight: 20,
    needsKeys: true,
    build: (data) => get(`/v2/process-instances/${pick(data.keys)}`),
  },
  {
    name: 'variables-by-instance',
    weight: 10,
    needsKeys: true,
    build: (data) => search('/v2/variables/search', {
      filter: { processInstanceKey: pick(data.keys) },
      page: { limit: 50 },
    }),
  },
  {
    name: 'element-instances-by-instance',
    weight: 5,
    needsKeys: true,
    build: (data) => search('/v2/element-instances/search', {
      filter: { processInstanceKey: pick(data.keys) },
      page: { limit: 50 },
    }),
  },
  {
    name: 'user-tasks-created',
    weight: 10,
    build: () => search('/v2/user-tasks/search', { filter: { state: 'CREATED' }, page: { limit: 50 } }),
  },
  {
    name: 'incidents-active',
    weight: 5,
    build: () => search('/v2/incidents/search', { filter: { state: 'ACTIVE' }, page: { limit: 20 } }),
  },
  {
    name: 'process-definitions',
    weight: 5,
    build: () => search('/v2/process-definitions/search', { page: { limit: 50 } }),
  },
].filter((q) => !DISABLED.includes(q.name));

function ok(res) {
  return res.status >= 200 && res.status < 300;
}

// Runs once. Checks auth and every query, and collects process instance keys for the key based queries.
export function setup() {
  if (AUTH === 'oidc') fetchToken();

  const topology = send([get('/v2/topology')], [{ step: 'setup' }])[0];
  console.log(`setup: GET /v2/topology -> ${topology.status}`);
  if (!ok(topology)) {
    throw new Error(`Cannot reach ${BASE_URL}/v2/topology (status ${topology.status}). Check QUERY_BASE_URL and credentials.`);
  }

  const keys = [];
  const found = send([search('/v2/process-instances/search', {
    sort: [{ field: 'startDate', order: 'DESC' }],
    page: { limit: 100 },
  })], [{ step: 'setup' }])[0];
  if (ok(found)) {
    for (const item of found.json().items || []) keys.push(item.processInstanceKey);
  }
  console.log(`setup: found ${keys.length} process instance keys to query by key`);

  const data = { keys, token: AUTH === 'oidc' && SHARED_TOKEN ? token : null };
  let passing = 0;
  for (const q of QUERIES) {
    if (q.needsKeys && keys.length === 0) {
      console.warn(`setup: ${q.name} -> skipped, no process instances found`);
      continue;
    }
    const res = send([q.build(data)], [{ step: 'setup' }])[0];
    const items = res.status === 200 && res.body && res.json().items ? res.json().items.length : '-';
    console.log(`setup: ${q.name} -> ${res.status}, items returned: ${items}`);
    if (ok(res)) passing++;
    else console.warn(`setup: ${q.name} body: ${String(res.body).slice(0, 200)}`);
  }
  if (passing === 0) {
    throw new Error('No query succeeded. Check the client authorizations (READ on the queried resources) and the secondary storage.');
  }
  return data;
}

let logged = 0;

function currentStep() {
  const segment = (RAMP_SECONDS + STEP_SECONDS) * 1000;
  const elapsed = Date.now() - exec.scenario.startTime;
  if (elapsed % segment < RAMP_SECONDS * 1000) return 'ramp';
  return String(STEPS[Math.min(Math.floor(elapsed / segment), STEPS.length - 1)]);
}

export default function (data) {
  if (data.token) {
    token = data.token;
    tokenExpiresAt = Number.MAX_SAFE_INTEGER;
  }
  const usable = QUERIES.filter((q) => !q.needsKeys || data.keys.length > 0);
  const total = usable.reduce((sum, q) => sum + q.weight, 0);
  const step = currentStep();

  const queries = [];
  for (let i = 0; i < BATCH; i++) {
    let roll = Math.random() * total;
    let query = usable[usable.length - 1];
    for (const q of usable) {
      roll -= q.weight;
      if (roll < 0) { query = q; break; }
    }
    queries.push(query);
  }

  let responses;
  try {
    responses = send(queries.map((q) => q.build(data)), queries.map((q) => ({ step, query: q.name })));
  } catch (e) {
    // A failed token request counts as failed queries, so it cannot hide behind a clean error rate.
    for (let i = 0; i < BATCH; i++) queryErrors.add(true, { step });
    if (logged < 3) { logged++; console.error(String(e).slice(0, 200)); }
    return;
  }

  responses.forEach((res, i) => {
    const success = ok(res);
    queryErrors.add(!success, { step });
    if (!success && logged < 3) {
      logged++;
      console.error(`${queries[i].name} -> ${res.status} ${String(res.body).slice(0, 200)}`);
    }
  });
}

const num = (n, digits = 0) => (typeof n === 'number' ? n.toFixed(digits) : '-');

export function handleSummary(data) {
  const metric = (name) => {
    const m = data.metrics[name];
    return m ? (m.values || m) : undefined;
  };
  const rows = [];
  rows.push('');
  rows.push(`Query benchmark: p95 target ${P95_MS} ms, max error rate ${MAX_ERROR_RATE * 100}%, ${STEP_SECONDS}s hold per step, batch ${BATCH}`);
  rows.push('step req/s | achieved | p50 ms | p95 ms | p99 ms | max ms | errors % | verdict');
  for (const rate of STEPS) {
    const dur = metric(`http_req_duration{step:${rate}}`);
    const reqs = metric(`http_reqs{step:${rate}}`);
    const errs = metric(`query_errors{step:${rate}}`);
    if (!dur || !reqs) {
      rows.push(`${String(rate).padStart(10)} | not reached`);
      continue;
    }
    const errorRate = errs ? errs.rate : 0;
    const pass = dur['p(95)'] < P95_MS && errorRate < MAX_ERROR_RATE;
    rows.push([
      String(rate).padStart(10),
      num(reqs.count / STEP_SECONDS, 1).padStart(8),
      num(dur.med).padStart(6),
      num(dur['p(95)']).padStart(6),
      num(dur['p(99)']).padStart(6),
      num(dur.max).padStart(6),
      num(errorRate * 100, 2).padStart(8),
      pass ? 'ok' : 'DEGRADED',
    ].join(' | '));
  }
  const dropped = metric('dropped_iterations');
  rows.push('');
  rows.push(`dropped iterations: ${dropped ? dropped.count : 0} (above 0 means k6 ran out of VUs, so the client, not the cluster, limited the rate)`);
  rows.push('achieved is measured over the hold only. If it is well below the step rate, the cluster could not keep up.');
  rows.push('');
  return { stdout: rows.join('\n') };
}

---
description: Set up a Web Modeler project and process application in a Camunda 8 Self-Managed environment. Idempotent. Creates a "Demo" project, fixes Keycloak permissions, creates a process application, and optionally configures Git sync and pulls process files from Git.
---

You are helping set up a Web Modeler project and process application in a Camunda 8 Self-Managed (SM) environment running on AKS with Keycloak OIDC. Every step is **idempotent** — safe to run multiple times.

The root of the repo is at the git root — find it with `git rev-parse --show-toplevel`.

---

## Step 0 — Discover environment

Read `<root>/config.mk` to get:
- `HOST_NAME` — cluster hostname (e.g. `dave01.aks.c8sm.com`)
- `DEFAULT_PASSWORD` — Keycloak admin password

If either is missing, ask the user before continuing.

Confirm Web Modeler is deployed:
```bash
kubectl get deployment camunda-web-modeler-restapi -n camunda --no-headers 2>/dev/null | head -1
```
If nothing is returned, stop — Web Modeler is not running.

Ask the user up front:

> **Would you like to configure Git sync automatically?**
> - **Yes (pull from Git)** → I'll create a `wm-automation` Keycloak user, create a process application, connect it to your Git repo, and **pull the process files from Git into Web Modeler**. This is the right choice when files already exist in Git.
> - **No** → I'll upload files from a local directory or GitHub, then give you UI instructions for Git sync.

**If yes**, ask:
> **Which Git provider?**
> - **GitLab** (recommended — uses a simple Project Access Token)
> - **Bitbucket** (uses an access token)
> - **GitHub** (requires a GitHub App — more setup)
> - **Azure DevOps** (requires an Azure App)

Then collect provider-specific details before running any steps:

**GitLab:**
- Repository URL (e.g. `https://gitlab.com/org/repo`)
- Branch name (e.g. `main`)
- GitLab project ID — numeric ID found in the repo's Settings → General page
- Project Access Token — create at repo Settings → Access Tokens with `api` scope

**Bitbucket:**
- Repository URL, branch name, access token

**GitHub:**
- Repository URL, branch name
- GitHub App client ID
- GitHub App installation ID
- GitHub App private key (PEM format)

**Azure DevOps:**
- Repository URL, branch name, Azure tenant ID, Azure client ID, certificate/PEM key

Also ask:
- **What should the process application be named?** (default: `My Process Application`)
- **Which Keycloak username(s) should have access to the project?** (e.g. `demo`) — these users will be added as `project_admin` collaborators so they can see the project in Web Modeler. The `wm-automation` service user creates the project but is not visible in the UI, so at least one human user must be added.

**If no**, ask:
> **Where are the process application files you want to upload?**
> - **Local directory** — provide an absolute or relative path. I'll find all `.bpmn`, `.dmn`, and `.form` files inside it.
> - **GitHub path** — provide `org/repo[/branch[/subdir]]`. I'll clone and list the files.
> - **Use a starter BPMN** — I'll create a minimal placeholder.

Resolve the file source:
- **Local path**: `find "<path>" -maxdepth 3 \( -name "*.bpmn" -o -name "*.dmn" -o -name "*.form" \)` — show and confirm.
- **GitHub path**: shallow clone, find files, show and confirm. Clean up the temp dir at the end.
- **Starter BPMN**: use the inline XML in Step 4 — no extra questions.

---

## Step 1 — Fix Web Modeler API permissions in Keycloak (idempotent)

**Why:** `KeycloakAuthentication.getPermissions()` in the Identity SDK reads the JWT `permissions` claim directly. The Helm chart's Keycloak init job assigns bare roles (`create`, `read`, etc.) to the `web-modeler-public-api` service account instead of the `:*` variants the converter checks for (`create:*`, `read:*`, etc.). Every API call returns 404 "Authority not present" until this is fixed.

**Get a Keycloak admin token:**
```bash
ADMIN_TOKEN=$(curl -s -X POST \
  "https://${HOST_NAME}/auth/realms/master/protocol/openid-connect/token" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "client_id=admin-cli" \
  --data-urlencode "username=admin" \
  --data-urlencode "password=${DEFAULT_PASSWORD}" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token','ERROR: '+str(d)))")
echo "Admin token: ${#ADMIN_TOKEN} chars"
```

**Find the `web-modeler-public-api` client and service account:**
```bash
WM_CLIENT_UUID=$(curl -s \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/clients?clientId=web-modeler-public-api" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['id'] if d else 'NOT_FOUND')")
echo "Client UUID: ${WM_CLIENT_UUID}"

SA_USER_ID=$(curl -s \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/clients/${WM_CLIENT_UUID}/service-account-user" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
echo "Service account ID: ${SA_USER_ID}"
```

**Check and assign the `:*` roles (idempotent):**
```bash
ASSIGNED=$(curl -s \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/users/${SA_USER_ID}/role-mappings/clients/${WM_CLIENT_UUID}" | \
  python3 -c "import json,sys; print([r['name'] for r in json.load(sys.stdin)])")

NEEDS_FIX=$(echo "${ASSIGNED}" | python3 -c "
import sys
roles = eval(sys.stdin.read())
missing = {'create:*','read:*','update:*','delete:*'} - set(roles)
print('MISSING:' + ','.join(missing) if missing else 'OK')
")
echo "Status: ${NEEDS_FIX}"
```

If output starts with `MISSING:`:
```bash
STAR_ROLES=$(curl -s \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/clients/${WM_CLIENT_UUID}/roles" | \
  python3 -c "
import json,sys
wanted = {'create:*','read:*','update:*','delete:*'}
print(json.dumps([r for r in json.load(sys.stdin) if r['name'] in wanted]))
")
curl -s -o /dev/null -w "Role assignment: HTTP %{http_code}\n" -X POST \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${STAR_ROLES}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/users/${SA_USER_ID}/role-mappings/clients/${WM_CLIENT_UUID}"
```

`204` = success.

---

## Step 2 — Get a Web Modeler public API token

```bash
WM_CLIENT_SECRET=$(curl -s \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/clients/${WM_CLIENT_UUID}/client-secret" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['value'])")

WM_TOKEN=$(curl -s -X POST \
  "https://${HOST_NAME}/auth/realms/camunda-platform/protocol/openid-connect/token" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=web-modeler-public-api" \
  --data-urlencode "client_secret=${WM_CLIENT_SECRET}" \
  --data-urlencode "audience=web-modeler-public-api" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token','ERROR: '+d.get('error_description','')))")
echo "Token: ${#WM_TOKEN} chars"
```

Verify:
```bash
curl -s -o /dev/null -w "API status: HTTP %{http_code}\n" -X POST \
  -H "Authorization: Bearer ${WM_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"filter":{}}' \
  "https://${HOST_NAME}/modeler/api/v1/projects/search"
```

`200` = proceed. `404` = the `:*` roles haven't propagated yet — wait 10s and retry Step 2.

---

## Step 3 — Find or create "Demo" project (idempotent)

```bash
PROJECTS=$(curl -s -X POST \
  -H "Authorization: Bearer ${WM_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"filter":{},"page":0,"size":50}' \
  "https://${HOST_NAME}/modeler/api/v1/projects/search")

PROJECT_ID=$(echo "${PROJECTS}" | python3 -c "
import json,sys
match = next((p['id'] for p in json.load(sys.stdin).get('items',[]) if p['name']=='Demo'), '')
print(match)
")

if [ -z "${PROJECT_ID}" ]; then
  RESP=$(curl -s -X POST \
    -H "Authorization: Bearer ${WM_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"name":"Demo"}' \
    "https://${HOST_NAME}/modeler/api/v1/projects")
  PROJECT_ID=$(echo "${RESP}" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  echo "Created project: ${PROJECT_ID}"
else
  echo "Project 'Demo' already exists: ${PROJECT_ID}"
fi
```

---

## Step 4 — Upload process files (idempotent — skip if using Git sync)

*Run this step only if the user chose **No** for Git sync in Step 0. When using Git sync (Step 5A), files come from Git via a pull — do not upload them here.*

Determine the `fileType` for each file from its extension: `.bpmn` → `bpmn`, `.dmn` → `dmn`, `.form` → `form`.

For each file confirmed in Step 0:

```bash
# Fetch already-uploaded files for this project (to skip duplicates)
EXISTING_FILES=$(curl -s -X POST \
  -H "Authorization: Bearer ${WM_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"filter\":{\"projectId\":\"${PROJECT_ID}\"},\"page\":0,\"size\":100}" \
  "https://${HOST_NAME}/modeler/api/v1/files/search")

# For each local file (repeat this block per file):
FILE_PATH="<absolute-path-to-file>"
FILE_NAME=$(basename "${FILE_PATH}" | sed 's/\.[^.]*$//')  # strip extension
FILE_TYPE="<bpmn|dmn|form>"
FILE_CONTENT=$(cat "${FILE_PATH}")

# Check if already uploaded
EXISTING_ID=$(echo "${EXISTING_FILES}" | python3 -c "
import json,sys
match = next((f['id'] for f in json.load(sys.stdin).get('items',[]) if f['name']=='${FILE_NAME}'), '')
print(match)
")

if [ -z "${EXISTING_ID}" ]; then
  PAYLOAD=$(python3 -c "
import json,sys
content = open('${FILE_PATH}').read()
print(json.dumps({
  'name': '${FILE_NAME}',
  'projectId': '${PROJECT_ID}',
  'fileType': '${FILE_TYPE}',
  'content': content
}))
")
  RESP=$(curl -s -X POST \
    -H "Authorization: Bearer ${WM_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}" \
    "https://${HOST_NAME}/modeler/api/v1/files")
  FILE_ID=$(echo "${RESP}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id','ERROR: '+str(json.load(open('/dev/stdin')))))" 2>/dev/null || echo "${RESP}")
  echo "Uploaded ${FILE_NAME}: ${FILE_ID}"
else
  echo "Already exists ${FILE_NAME}: ${EXISTING_ID}"
  FILE_ID="${EXISTING_ID}"
fi
```

**Starter BPMN fallback** — use this inline XML if the user chose "Use a starter BPMN" in Step 0. Name: `payment-process`, type: `bpmn`.

```
<?xml version="1.0" encoding="UTF-8"?><definitions xmlns="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:zeebe="http://camunda.org/schema/zeebe/1.0" xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" id="Definitions_1" targetNamespace="http://bpmn.io/schema/bpmn"><process id="payment-process" name="Payment Processing" isExecutable="true"><startEvent id="start" name="Payment initiated"><outgoing>flow1</outgoing></startEvent><endEvent id="end" name="Payment complete"><incoming>flow1</incoming></endEvent><sequenceFlow id="flow1" sourceRef="start" targetRef="end"/></process><bpmndi:BPMNDiagram id="BPMNDiagram_1"><bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="payment-process"><bpmndi:BPMNShape id="start_di" bpmnElement="start"><dc:Bounds x="152" y="82" width="36" height="36"/></bpmndi:BPMNShape><bpmndi:BPMNShape id="end_di" bpmnElement="end"><dc:Bounds x="302" y="82" width="36" height="36"/></bpmndi:BPMNShape></bpmndi:BPMNPlane></bpmndi:BPMNDiagram></definitions>
```

After uploading all files, track the **first `.bpmn` file's ID** as `MAIN_BPMN_ID` — used as `mainProcessContent` in Step 5A-v.

Print:
```
✓ Project:  Demo            (${PROJECT_ID})
✓ Files uploaded: <count>
  <list each: name → id>
  URL: https://${HOST_NAME}/modeler
```

---

## Step 5A — Automated: Create process application, seed from Git, and connect Git sync

*Run this path only if the user chose automated Git sync (Yes) in Step 0.*

**Flow:** Clone the Git repo → create process application with real BPMN content → upload remaining files → configure Git sync settings.

**WM 8.9 Git sync — key facts:**
- Use the **`path`** field in settings to specify a subdirectory (e.g. `src/main/resources/PaymentProcessing`). This is what the UI labels "Repository path (optional)".
- `/pull` returns `{"data":{"pulled":false}}` when WM and git are in sync; `{"errors":[{"reason":"GIT_CONFLICT"}]}` when there are local changes — in both cases git content replaces WM content and the pull succeeds.
- `/push` will **overwrite all git content** with the WM process application files. **NEVER call `/push` automatically.** It cannot be undone without a force-reset on the remote branch.
- Correct flow: create PA with placeholder BPMN → configure git sync with `path` → pull from git.

**Background:** The Web Modeler internal API (used for process apps and Git sync) requires a user-scoped token — not the M2M service account token. The `camunda-identity` Keycloak client supports direct access grants and issues tokens with `web-modeler-api` in the audience, which the internal API accepts. A new Keycloak user also needs their record bootstrapped in Web Modeler's database via `POST /api/internal/login` before the internal API will accept their requests.

### 5A-i — Get the camunda-identity client secret

```bash
CI_UUID=$(curl -s \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/clients?clientId=camunda-identity" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")

CI_SECRET=$(curl -s \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/clients/${CI_UUID}/client-secret" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['value'])")
echo "camunda-identity secret: ${#CI_SECRET} chars"
```

### 5A-ii — Create the `wm-automation` Keycloak user (idempotent)

```bash
EXISTING=$(curl -s \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/users?username=wm-automation&exact=true" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")

if [ -z "${EXISTING}" ]; then
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "username": "wm-automation",
      "email": "wm-automation@example.com",
      "firstName": "WM",
      "lastName": "Automation",
      "enabled": true,
      "credentials": [{"type":"password","value":"'"${DEFAULT_PASSWORD}"'","temporary":false}]
    }' \
    "https://${HOST_NAME}/auth/admin/realms/camunda-platform/users")
  echo "User creation: HTTP ${HTTP}"

  EXISTING=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "https://${HOST_NAME}/auth/admin/realms/camunda-platform/users?username=wm-automation&exact=true" | \
    python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")
fi
AUTOMATION_USER_ID="${EXISTING}"
echo "wm-automation user ID: ${AUTOMATION_USER_ID}"
```

### 5A-iii — Get a user-scoped token and bootstrap the WM user record

```bash
AUTO_TOKEN=$(curl -s -X POST \
  "https://${HOST_NAME}/auth/realms/camunda-platform/protocol/openid-connect/token" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "client_id=camunda-identity" \
  --data-urlencode "client_secret=${CI_SECRET}" \
  --data-urlencode "username=wm-automation" \
  --data-urlencode "password=${DEFAULT_PASSWORD}" \
  --data-urlencode "scope=openid" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token','ERROR: '+str(d)))")
echo "Auto token: ${#AUTO_TOKEN} chars"

# Decode sub and name from token
AUTO_SUB=$(echo "${AUTO_TOKEN}" | cut -d. -f2 | python3 -c "
import sys,base64,json
p=sys.stdin.read().strip()+'=='
print(json.loads(base64.urlsafe_b64decode(p))['sub'])
")

# Bootstrap the WM user record (idempotent — returns existing record if already present)
LOGIN_RESP=$(curl -s -w "\nHTTP: %{http_code}" -X POST \
  -H "Authorization: Bearer ${AUTO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"iamId\":\"${AUTO_SUB}\",\"name\":\"wm-automation\",\"email\":\"wm-automation@example.com\"}" \
  "https://${HOST_NAME}/modeler/api/internal/login")
echo "Login bootstrap: ${LOGIN_RESP}"

# Verify internal API is now accessible
SELF=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${AUTO_TOKEN}" \
  "https://${HOST_NAME}/modeler/api/internal/self")
echo "Internal API /self: HTTP ${SELF}"
```

`200` on `/self` means the user record exists and the internal API is accessible.

### 5A-iv — Assign Web Modeler realm roles + add as project collaborator (idempotent)

The automation user needs two things:
1. **Keycloak realm roles** `Web Modeler` and `Web Modeler Admin` — these add `web-modeler-api` audience and `write:*`/`admin:*` permissions to the JWT. Without them, `SelfManagedInternalApiTokenOrganizationPermissionEvaluator` throws `InvalidClaimException` and returns 404 on all internal API write operations.
2. **Project collaborator** access — required for the process application creation to find the project.

```bash
# Assign Web Modeler realm roles
ROLES_PAYLOAD=$(curl -s \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/roles" | \
  python3 -c "
import json,sys
wanted = {'Web Modeler', 'Web Modeler Admin'}
print(json.dumps([r for r in json.load(sys.stdin) if r['name'] in wanted]))
")
ROLES_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${ROLES_PAYLOAD}" \
  "https://${HOST_NAME}/auth/admin/realms/camunda-platform/users/${AUTOMATION_USER_ID}/role-mappings/realm")
echo "Realm role assignment: HTTP ${ROLES_HTTP}"

# Add wm-automation as project collaborator (needed for internal API access)
COLLAB_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  -H "Authorization: Bearer ${WM_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"projectId\":\"${PROJECT_ID}\",\"email\":\"wm-automation@example.com\",\"role\":\"project_admin\"}" \
  "https://${HOST_NAME}/modeler/api/v1/collaborators")
echo "Add wm-automation collaborator: HTTP ${COLLAB_HTTP}"

# Add each human user collected in Step 0 as a collaborator.
# The project is created by the M2M service account and wm-automation, neither of which
# appears in the Web Modeler UI — human users must be explicitly granted access.
# Look up each username's email from Keycloak, then add:
for USERNAME in ${HUMAN_USERS}; do
  EMAIL=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "https://${HOST_NAME}/auth/admin/realms/camunda-platform/users?username=${USERNAME}&exact=true" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['email'] if d else '')")
  if [ -z "${EMAIL}" ]; then
    echo "WARNING: user '${USERNAME}' not found in Keycloak — skipping"
    continue
  fi
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer ${WM_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"projectId\":\"${PROJECT_ID}\",\"email\":\"${EMAIL}\",\"role\":\"project_admin\"}" \
    "https://${HOST_NAME}/modeler/api/v1/collaborators")
  echo "Add ${USERNAME} (${EMAIL}) as collaborator: HTTP ${HTTP}"
done
```

After assigning realm roles, get a **fresh token** — the old token won't have the new permissions:
```bash
AUTO_TOKEN=$(curl -s -X POST \
  "https://${HOST_NAME}/auth/realms/camunda-platform/protocol/openid-connect/token" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "client_id=camunda-identity" \
  --data-urlencode "client_secret=${CI_SECRET}" \
  --data-urlencode "username=wm-automation" \
  --data-urlencode "password=${DEFAULT_PASSWORD}" \
  --data-urlencode "scope=openid" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
```

Verify the new token has `web-modeler-api` in the audience:
```bash
echo "${AUTO_TOKEN}" | cut -d. -f2 | python3 -c "
import sys,base64,json
p=sys.stdin.read().strip()+'=='
d=json.loads(base64.urlsafe_b64decode(p))
print('aud:', d.get('aud'))
print('web-modeler-api perms:', d.get('permissions',{}).get('web-modeler-api',[]))
"
```
Must show `web-modeler-api` in `aud` and `['write:*', 'admin:*']` in permissions.

`204` on the collaborator PUT = success. `409` = already a collaborator (fine).

### 5A-v — Create process application with a minimal placeholder BPMN

The process application must be created with a `mainProcessContent` BPMN to satisfy the API. Use a minimal placeholder — the real files come from git in the pull step.

```bash
MINIMAL_BPMN='<?xml version="1.0" encoding="UTF-8"?><definitions xmlns="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" id="Definitions_1" targetNamespace="http://bpmn.io/schema/bpmn"><process id="placeholder" name="Placeholder" isExecutable="true"><startEvent id="start"><outgoing>flow1</outgoing></startEvent><endEvent id="end"><incoming>flow1</incoming></endEvent><sequenceFlow id="flow1" sourceRef="start" targetRef="end"/></process><bpmndi:BPMNDiagram id="BPMNDiagram_1"><bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="placeholder"><bpmndi:BPMNShape id="start_di" bpmnElement="start"><dc:Bounds x="152" y="82" width="36" height="36"/></bpmndi:BPMNShape><bpmndi:BPMNShape id="end_di" bpmnElement="end"><dc:Bounds x="302" y="82" width="36" height="36"/></bpmndi:BPMNShape></bpmndi:BPMNPlane></bpmndi:BPMNDiagram></definitions>'

python3 -c "
import json
print(json.dumps({
  'name': '${PA_NAME}',
  'projectId': '${PROJECT_ID}',
  'mainProcessContent': open('/dev/stdin').read()
}))
" <<< "${MINIMAL_BPMN}" > "${SCRATCH}/payload_pa.json"

PA_RESP=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer ${AUTO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "@${SCRATCH}/payload_pa.json" \
  "https://${HOST_NAME}/modeler/api/internal/process-applications")

PA_HTTP=$(echo "${PA_RESP}" | grep "HTTP_STATUS:" | cut -d: -f2)
PA_BODY=$(echo "${PA_RESP}" | grep -v "HTTP_STATUS:")
echo "Process application creation: HTTP ${PA_HTTP}"

# Response is wrapped: {"data": {"id": "...", ...}}
PA_ID=$(echo "${PA_BODY}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null)
echo "Process application ID: ${PA_ID}"
```

`200` = created.

### 5A-vi — Configure Git sync settings with optional subdirectory path

`204` = configured. `400` = check credentials or repo URL.

Use the **`path`** field to specify a subdirectory within the repo (this is what the UI labels "Repository path (optional)"). If the files are at the repo root, omit it.

**GitLab:**
```bash
python3 -c "
import json
payload = {
  'provider': 'GITLAB',
  'repositoryUrl': '${GITLAB_REPO_URL}',
  'branchName': '${GITLAB_BRANCH}',
  'projectId': '${GITLAB_PROJECT_ID}',
  'projectAccessToken': '${GITLAB_PAT}'
}
if '${GITLAB_PATH}':
    payload['path'] = '${GITLAB_PATH}'  # e.g. 'src/main/resources/PaymentProcessing'
print(json.dumps(payload))
" > "${SCRATCH}/payload_git.json"

GIT_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  -H "Authorization: Bearer ${AUTO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "@${SCRATCH}/payload_git.json" \
  "https://${HOST_NAME}/modeler/api/internal/process-applications/${PA_ID}/settings")
echo "Git sync config: HTTP ${GIT_HTTP}"
```

**GitHub:**
```bash
python3 << PYEOF
import json
with open('<path-to-pem>', 'r') as f:
    pem = f.read()
payload = {
    'provider': 'GITHUB',
    'repositoryUrl': '${GITHUB_REPO_URL}',
    'branchName': '${GITHUB_BRANCH}',
    'clientId': '${GITHUB_APP_CLIENT_ID}',
    'installationId': '${GITHUB_APP_INSTALLATION_ID}',
    'pemKey': pem
}
if '${GITHUB_PATH}':
    payload['path'] = '${GITHUB_PATH}'  # e.g. 'src/main/resources/PaymentProcessing'
with open('${SCRATCH}/payload_git.json', 'w') as f:
    json.dump(payload, f)
PYEOF

GIT_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  -H "Authorization: Bearer ${AUTO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "@${SCRATCH}/payload_git.json" \
  "https://${HOST_NAME}/modeler/api/internal/process-applications/${PA_ID}/settings")
echo "Git sync config: HTTP ${GIT_HTTP}"
```

### 5A-vii — Pull from Git

This replaces the placeholder with the real files from git (at the configured `path`).

```bash
PULL_RESP=$(curl -s -X POST \
  -H "Authorization: Bearer ${AUTO_TOKEN}" \
  "https://${HOST_NAME}/modeler/api/internal/process-applications/${PA_ID}/pull")
echo "Pull: ${PULL_RESP}"
```

Expected responses:
- `{"data":{"pulled":true}}` — files pulled successfully
- `{"data":{"pulled":false}}` — already in sync (no changes)
- `{"errors":[{"reason":"GIT_CONFLICT"}]}` — conflict detected; git version wins and replaces WM files (this is a success — check the PA to confirm files are now from git)

**DO NOT call `/push` automatically.** Pushing overwrites git content with whatever is in the WM process application and cannot be undone without a force-reset.

Print final summary:
```
✓ Project:             Demo                     (${PROJECT_ID})
✓ Process Application: ${PA_NAME}               (${PA_ID})
✓ Git sync:            ${PROVIDER} → ${REPO_URL} @ ${BRANCH} / ${PATH}
✓ Pulled from Git:     complete
  Open: https://${HOST_NAME}/modeler
```

---

## Step 5B — UI guidance: Create process application and connect Git manually

*Run this path if the user chose not to automate Git sync.*

Tell the user:

> **Open Web Modeler:** `https://${HOST_NAME}/modeler`
>
> You will see the **Demo** project with a `payment-process.bpmn` file.
>
> **Create a Process Application:**
> 1. Open the **Demo** project
> 2. Click **+ Create** → **Process Application**
> 3. Name it after your process and confirm
> 4. The uploaded files are already in the project — drag them into the process application, or use the **Link existing file** option if available
>
> **Connect Git:**
> 1. Inside the Process Application, click the **Git sync** icon (top-right area)
> 2. Choose your provider (GitLab, GitHub, Azure, Bitbucket)
> 3. Fill in repository URL, branch, and credentials:
>    - **GitLab:** Project Access Token (repo Settings → Access Tokens, `api` scope) + numeric Project ID (repo Settings → General)
>    - **GitHub:** Requires a GitHub App (not a PAT) — create at github.com/settings/apps
>    - **Bitbucket:** Access token from repo Settings → Access tokens
> 4. Click **Connect** then **Push** to sync your process files to the repo

---

## Troubleshooting

**404 "Authority not present" on public API calls**

Check that `:*` roles are in the JWT:
```bash
echo "${WM_TOKEN}" | cut -d. -f2 | python3 -c "
import sys,base64,json
p=sys.stdin.read().strip()+'=='
print(json.loads(base64.urlsafe_b64decode(p)).get('permissions',{}))
"
```
Must contain `create:*`, `read:*`, `update:*`, `delete:*` under `web-modeler-public-api`. If not, re-run Step 1.

**Internal API returns 500 / user not found**

The `wm-automation` user record wasn't created. Re-run Step 5A-iii — the `/api/internal/login` bootstrap call must succeed (200) before any other internal API calls will work.

**Process application creation returns 404 (despite /self returning 200)**

The automation user's JWT is missing `web-modeler-api` audience. This is caused by missing Keycloak realm roles. Re-run Step 5A-iv to assign `Web Modeler` and `Web Modeler Admin` realm roles, then get a fresh token. Confirm with:
```bash
echo "${AUTO_TOKEN}" | cut -d. -f2 | python3 -c "
import sys,base64,json
p=sys.stdin.read().strip()+'=='
print(json.loads(base64.urlsafe_b64decode(p)).get('aud',[]))
"
```
Must include `web-modeler-api`.

**Process application creation returns 403**

The automation user isn't a project collaborator. Re-run the collaborator PUT in Step 5A-iv.

**Git sync config returns 400**

For GitLab: verify the `projectId` is the **numeric** project ID (not the path). Find it in the repo's Settings → General page in GitLab.
For GitHub: GitHub App must be installed on the repo and the installation ID must match.

**Pull from Git returns `{"data":{"pulled":false}}`**

WM and git are already in sync — no changes needed. If you expected files to be pulled, check that the `path` setting matches the directory in git that contains the BPMN/DMN/form files.

**Pull from Git returns `{"errors":[{"reason":"GIT_CONFLICT"}]}`**

This means WM detected local changes that differ from git. **Git wins** — the pull still succeeded and replaced the WM files with the git versions. Verify by fetching the PA detail and checking file revision numbers increased.

**Pull from Git returns 404**

In WM 8.9, the pull endpoint is `/pull` (not `/sync` — `/sync` returns 404 in this version). Verify you are calling:
```bash
POST /modeler/api/internal/process-applications/${PA_ID}/pull
```
If that also 404s, check pod logs:
```bash
kubectl logs -n camunda -l app.kubernetes.io/name=web-modeler-restapi --tail=20 | grep "process-application"
```

**NEVER call `/push` unless the user explicitly requests it**

`POST .../push` (HTTP 200) destroys all files in the git repo and replaces them with the current WM process application contents. This cannot be undone without a force-reset on the remote branch. The skill must never call this endpoint automatically.

**Token endpoint returns `unauthorized_client`**

Check that the `camunda-identity` client has **Direct access grants** enabled in Keycloak:
```
https://${HOST_NAME}/auth/admin → camunda-platform realm → Clients → camunda-identity → Settings → Authentication flow
```

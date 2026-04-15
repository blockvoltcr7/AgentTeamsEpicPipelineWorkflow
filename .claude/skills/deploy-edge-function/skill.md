---
name: deploy-edge-function
description: Deploy Supabase Edge Functions to production or staging with automated verification and health checks. Use when deploying edge functions, verifying deployments, or troubleshooting function issues. Handles pre-deployment validation, deployment execution, and post-deployment verification.
---

# Deploy Supabase Edge Function

Deploy Supabase Edge Functions safely with automated verification and comprehensive error handling.

## Mission

Deploy edge functions to Supabase, verify deployment success, and provide clear feedback about function status and accessibility.

---

## Input Detection

### Function Name Resolution

**Priority 1: Explicit Argument**
```
User: deploy ghl-program-webhook
User: deploy ghl-program-webhook --project-ref abc123
```
Parse function name from command arguments.

**Priority 2: Context Inference**
Detect function name from:
1. Recent file paths (e.g., `supabase/functions/<name>/`)
2. Conversation context (function mentioned in last 5 messages)
3. Current working directory

**Priority 3: Ask User**
If no function name detected:
```
I need to know which Edge Function to deploy.

Available functions in supabase/functions/:
- function-1
- function-2
- function-3

Which function should I deploy?
```

### Project Reference Detection

**Priority 1: Explicit --project-ref flag**
```
User: deploy my-function --project-ref ycalfomyshtxvdikeogf
```

**Priority 2: Infer from supabase CLI config**
```bash
supabase status --json | jq -r '.project_ref'
```

**Priority 3: Ask user**
```
Which Supabase project should I deploy to?

Options:
1. Use linked project (run `supabase status` to check)
2. Specify project ref explicitly

Please provide the project ref or confirm linked project.
```

---

## Pre-Deployment Checks

### Step 1: Verify Function Exists

```bash
cd apps/web
ls -la supabase/functions/<function-name>/
```

**Expected structure:**
```
supabase/functions/<function-name>/
├── index.ts (required)
├── _helper-module.ts (optional)
└── deno.json (optional)
```

**If missing:**
```markdown
❌ Function not found: `<function-name>`

Available functions:
- function-1
- function-2

Did you mean one of these?
```

### Step 2: TypeScript Compilation Check (Optional)

Run TypeScript check if project has `tsconfig.json`:

```bash
cd apps/web
npx tsc --noEmit
```

**If errors found:**
```markdown
⚠️ TypeScript Compilation Errors Detected

Found X errors in the codebase. Deploy anyway?

[Show first 3 errors]

Options:
1. Fix errors first (recommended)
2. Deploy anyway (function may fail at runtime)
```

### Step 3: Check for Uncommitted Changes (Optional)

```bash
git diff --name-only supabase/functions/<function-name>/
```

**If uncommitted changes:**
```markdown
⚠️ Uncommitted Changes Detected

The following files have uncommitted changes:
- supabase/functions/<function-name>/index.ts
- supabase/functions/<function-name>/_helper.ts

Options:
1. Continue deployment (recommended - deploy latest code)
2. Commit changes first
3. Cancel deployment
```

---

## Deployment Execution

### Step 1: Navigate to Project Root

```bash
cd apps/web
```

### Step 2: Deploy Function

**With project ref:**
```bash
supabase functions deploy <function-name> --project-ref <ref>
```

**Without project ref (uses linked project):**
```bash
supabase functions deploy <function-name>
```

### Step 3: Capture Deployment Output

**Success Output:**
```
Deploying function <function-name>
Bundled <function-name> to <size>
Function deployed successfully
Function URL: https://<ref>.supabase.co/functions/v1/<function-name>
```

**Parse output for:**
- Deployment status (success/failure)
- Function URL
- Bundle size
- Any warnings or errors

---

## Post-Deployment Verification

### Test 1: Function Accessibility

Test if function is reachable (expect 401 or 405 for protected endpoints):

```bash
curl -i https://<ref>.supabase.co/functions/v1/<function-name>
```

**Expected responses:**
- `401 Unauthorized` ✅ (function live, JWT verification active)
- `405 Method Not Allowed` ✅ (function live, GET not allowed)
- `200 OK` ✅ (function live and responding)
- `404 Not Found` ❌ (deployment failed or incorrect URL)
- `502 Bad Gateway` ❌ (function crashed on startup)
- `504 Gateway Timeout` ❌ (function startup timeout)

### Test 2: Check Recent Logs

Fetch last 10 log entries to verify startup:

```bash
supabase functions logs <function-name> --project-ref <ref> --limit 10
```

**Look for:**
- ✅ Initialization messages
- ✅ Environment variables loaded
- ✅ No startup errors
- ❌ Error stack traces
- ❌ Missing environment variables
- ❌ Module not found errors

### Test 3: Verify Environment Secrets (If Applicable)

**For functions requiring secrets:**

```bash
supabase secrets list --project-ref <ref>
```

**Check that required secrets exist:**
- API keys
- Database credentials
- Third-party service tokens

**If secrets missing:**
```markdown
⚠️ Missing Required Secrets

Your function requires these secrets:
- RESEND_API_KEY (missing)
- STRIPE_SECRET_KEY (found ✅)

Set missing secrets:
supabase secrets set RESEND_API_KEY=your-key --project-ref <ref>
```

---

## Deployment Report

After successful deployment, present comprehensive report:

```markdown
## ✅ Deployment Complete: `<function-name>`

### Deployment Details
- **Status:** Successfully deployed
- **Project:** <project-name> (<project-ref>)
- **Function URL:** `https://<ref>.supabase.co/functions/v1/<function-name>`
- **Version:** <version-number>
- **Bundle Size:** <size>
- **Deployment Time:** <timestamp>

### Verification Results

**1. Function Accessibility:** ✅ Success
- URL responds with <status-code> (<expected-behavior>)
- Confirms function is live and <protection-status>

**2. Startup Logs:** ✅ Healthy
- Function initialized successfully
- No startup errors detected
- Environment variables loaded: <list>

**3. Environment Secrets:** ✅ All Present
- REQUIRED_SECRET_1 ✅
- REQUIRED_SECRET_2 ✅
- Optional: OPTIONAL_SECRET_1 ✅

### Function Configuration
- **HTTP Methods:** <allowed-methods>
- **Authentication:** <auth-config>
- **CORS:** <cors-status>
- **Timeout:** <timeout-seconds>s

### Next Steps

The function is now live and ready for use. To test:

1. **Test Endpoint:**
   ```bash
   curl -X POST https://<ref>.supabase.co/functions/v1/<function-name> \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{"test": "data"}'
   ```

2. **Monitor Logs:**
   ```bash
   supabase functions logs <function-name> --project-ref <ref> --follow
   ```

3. **View in Dashboard:**
   https://supabase.com/dashboard/project/<ref>/functions

---

**Deployment ID:** <deployment-id>
**Deployed By:** Claude Code Deployment Assistant
```

---

## Error Handling

### Error: Function Not Found

```markdown
❌ Deployment Failed: Function Not Found

Cannot find function `<function-name>` in `supabase/functions/`

Available functions:
- function-1
- function-2
- function-3

Did you mean one of these?
```

### Error: Project Not Linked

```markdown
❌ Deployment Failed: No Supabase Project Linked

Please link a project or specify project ref:

**Option 1: Link project**
```bash
supabase link --project-ref <your-project-ref>
```

**Option 2: Deploy with explicit ref**
```bash
deploy <function-name> --project-ref <ref>
```
```

### Error: Authentication Failed

```markdown
❌ Deployment Failed: Authentication Error

Supabase CLI authentication failed. Please login:

```bash
supabase login
```

Then retry deployment.
```

### Error: Deployment Timeout

```markdown
❌ Deployment Failed: Timeout

The deployment took longer than expected and timed out.

Possible causes:
- Large function bundle size
- Network connectivity issues
- Supabase service outage

Try again in a few moments.
```

### Error: Function Crashed on Startup

```markdown
❌ Deployment Failed: Function Crashed

The function deployed but crashed during startup.

**Recent error logs:**
```
[error log excerpt]
```

**Common causes:**
- Syntax errors in TypeScript/JavaScript
- Missing dependencies (check imports)
- Missing environment variables
- Invalid module imports

**Next steps:**
1. Check logs: `supabase functions logs <function-name> --limit 20`
2. Fix errors in code
3. Redeploy with fixes
```

---

## Advanced Options

### Deploy with No Verification JWT

For public endpoints that don't require authentication:

```bash
supabase functions deploy <function-name> --no-verify-jwt --project-ref <ref>
```

**Warning:** Only use for truly public endpoints. Most functions should verify JWT.

### Deploy to Specific Region

```bash
supabase functions deploy <function-name> --project-ref <ref> --region us-west-1
```

### Deploy with Import Map

```bash
supabase functions deploy <function-name> --import-map supabase/functions/<function-name>/deno.json --project-ref <ref>
```

### Deploy Multiple Functions

```bash
# Deploy all functions in supabase/functions/
for func in supabase/functions/*/; do
  func_name=$(basename "$func")
  supabase functions deploy "$func_name" --project-ref <ref>
done
```

---

## Deployment Checklist

Before deploying, verify:

- [ ] Function code tested locally
- [ ] TypeScript compilation passes (if applicable)
- [ ] All required environment variables documented
- [ ] Function handles errors gracefully
- [ ] CORS configured correctly (if public API)
- [ ] Authentication/authorization implemented (if needed)
- [ ] Rate limiting considered (if public)
- [ ] Logs structured and informative
- [ ] Function URL documented in README
- [ ] Team notified of deployment (if production)

---

## Common Patterns

### Pattern 1: Deploy and Test

```bash
# Deploy
supabase functions deploy my-function --project-ref abc123

# Test immediately
curl -X POST https://abc123.supabase.co/functions/v1/my-function \
  -H "Content-Type: application/json" \
  -d '{"test": true}'

# Monitor logs
supabase functions logs my-function --project-ref abc123 --follow
```

### Pattern 2: Deploy with Secret Update

```bash
# Update secrets first
supabase secrets set API_KEY=new-key --project-ref abc123

# Then deploy
supabase functions deploy my-function --project-ref abc123
```

### Pattern 3: Rollback to Previous Version

```bash
# List deployments
supabase functions list --project-ref abc123

# Deploy specific version (if supported)
# Note: Supabase doesn't have native rollback - redeploy previous code
```

---

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Deploy Edge Function

on:
  push:
    branches: [main]
    paths:
      - 'apps/web/supabase/functions/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Supabase CLI
        uses: supabase/setup-cli@v1

      - name: Deploy Function
        run: |
          supabase functions deploy my-function \
            --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

---

## Usage

This skill is invoked via the `/deploy` command or automatically when deploying edge functions.

**Workflow:**
1. Detect function name and project reference
2. Run pre-deployment checks (function exists, optional TypeScript compilation)
3. Deploy function to Supabase
4. Run post-deployment verification (accessibility, logs, secrets)
5. Generate comprehensive deployment report
6. Handle errors gracefully with clear guidance

The skill provides automated verification and clear feedback for safe edge function deployments.

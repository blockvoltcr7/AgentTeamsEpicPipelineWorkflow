# LiveKit Agent Architecture Reference

## Dispatch Model

The OS HQ agent uses **explicit dispatch** (not automatic). This means:

1. The agent registers with `agentName: "os-hq-agent"` in `ServerOptions`
2. The web app's token server includes a `RoomAgentDispatch` in the access token
3. LiveKit matches the `agentName` in the dispatch to the registered agent

### Key Files

| File | Role |
|---|---|
| `apps/agent/src/main.ts` | Agent entrypoint — `ServerOptions({ agentName: "os-hq-agent" })`, metadata parsing, greeting |
| `apps/agent/src/agent.ts` | Agent class — system prompt, tool wiring (`voice.Agent` subclass) |
| `apps/agent/src/tools/ghl-tools.ts` | 5 GHL API tool definitions using `llm.tool()` + Zod schemas |
| `apps/agent/src/tools/ghl-client.ts` | GHL HTTP client — `ghlFetch<T>(path)` with error handling |
| `apps/web/lib/livekit/token-server.ts` | Token generation with `RoomAgentDispatch` + user metadata |
| `apps/web/app/actions/livekit-token-actions.ts` | Server action — member auth, GHL location resolution, token generation |
| `apps/web/components/livekit/VoiceAgentView.tsx` | Frontend — `useSession(tokenSource, { agentName })` |

### Agent Pipeline

```
Microphone → Silero VAD → Deepgram Nova-3 (STT) → GPT-4.1-mini (LLM) → Cartesia Sonic-3 (TTS) → Speaker
                                                        ↕
                                                  GHL API Tools
                                               (backend-to-backend)
```

- **VAD:** Silero — prewarmed in `defineAgent.prewarm`, cached on `proc.userData.vad`
- **STT:** `deepgram/nova-3:multi` (inference string shortcut)
- **LLM:** `openai/gpt-4.1-mini` (inference string shortcut)
- **TTS:** `cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc` (with voice ID)
- **Turn detection:** `livekit.turnDetector.MultilingualModel()` (server-side)

### GHL API Tools

The agent has 5 tools that call the GHL microservice (`GHL_SYNC_SERVICE_URL`) for business data:

| Tool | Endpoint | Purpose |
|---|---|---|
| `getPipelineHealth` | `/api/pipeline-health/{locationId}` | Deal pipeline status, stuck deals, stage distribution |
| `getRevenuePulse` | `/api/revenue-pulse/{locationId}` | MRR, active subscriptions, past-due payments |
| `searchContacts` | `/api/contacts/search/{locationId}` | Search contacts by tag, source, date |
| `getContactsSummary` | `/api/contacts/summary/{locationId}` | Total contacts, lead source breakdown |
| `getDealsBySource` | `/api/deals/by-source/{locationId}` | Deal attribution by marketing source |

**Location context flow:**
1. `livekit-token-actions.ts` resolves `locationId` from DB: `users → userLocationAccess → locations`
2. `token-server.ts` embeds `{ userId, locationId }` in JWT metadata
3. `main.ts` parses `participant.metadata` → stores in `AgentUserData`
4. Tools access `ctx.userData.locationId` — guard with `llm.ToolError` if missing

### Room Naming Convention

Room names follow the pattern: `agent-room-{supabase_user_id}-{timestamp}`

**Critical:** Room names MUST be unique per session. LiveKit rooms stay active briefly after disconnect; reusing the same room name causes the agent to not dispatch.

### LiveKit Cloud CLI Reference

```bash
lk cloud auth                  # Authenticate with LiveKit Cloud
lk project list                # List linked projects
lk project set-default "name"  # Set default project for CLI commands
lk agent create                # Register a new agent (generates livekit.toml)
lk agent deploy                # Build & push Docker image to LiveKit Cloud
lk agent status                # Show status, replicas, version, region
lk agent logs                  # Stream agent logs
lk agent rollback              # Rollback to previous version (no rebuild)
lk agent update-secrets        # Update environment secrets
lk agent secrets               # List configured secret names
```

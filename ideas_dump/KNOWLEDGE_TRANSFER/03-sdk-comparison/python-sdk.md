# Python SDK

Location: `/python/`

Package: Install via pip (package name per `python/pyproject.toml` or `setup.cfg`).

## Public API

Exports (`python/copilot/__init__.py`):

- `CopilotClient` — main client class
- `CopilotSession` — conversation session
- `define_tool` — decorator/factory for tools with Pydantic params
- `PermissionHandler` (with `.approve_all`) — built-in permission handlers
- `CommandDefinition`, `CommandContext` — slash commands
- `convert_mcp_call_tool_result` — MCP adapter
- `SessionFsConfig` — virtual filesystem config
- `ProviderConfig` — BYOK provider config
- `ElicitationHandler`, `PermissionHandler` — handler protocols

## Client lifecycle

```python
import asyncio
from copilot import CopilotClient, PermissionHandler

async def main():
    async with CopilotClient() as client:
        session = await client.create_session(
            model="gpt-5",
            on_permission_request=PermissionHandler.approve_all,
        )

        async for event in session.events():
            if event.type == "assistant.message":
                print(event.data.content)

asyncio.run(main())
```

Context-manager usage auto-stops the client. Alternative explicit form:

```python
client = CopilotClient()
await client.start()
# ...
await client.stop()
```

## Session example

```python
import asyncio
from copilot import CopilotClient, PermissionHandler, define_tool
from pydantic import BaseModel, Field

class WeatherArgs(BaseModel):
    location: str = Field(description="City name")

@define_tool(name="get_weather", description="Fetch weather")
async def get_weather(args: WeatherArgs, invocation) -> dict:
    return {"temp": 72, "location": args.location}

async def main():
    async with CopilotClient() as client:
        session = await client.create_session(
            model="gpt-5",
            tools=[get_weather],
            on_permission_request=PermissionHandler.approve_all,
            streaming=True,
        )

        message = await session.send_and_wait(prompt="Weather in NYC?")
        print(message.data.content)

asyncio.run(main())
```

## Custom agents

```python
custom_agents = [
    {
        "name": "researcher",
        "display_name": "Research Agent",
        "tools": ["grep", "glob", "view"],
        "prompt": "You are a read-only researcher.",
        "infer": True,
    },
    {
        "name": "editor",
        "tools": ["view", "edit", "bash"],
        "prompt": "You are a code editor.",
        "infer": True,
    },
]

session = await client.create_session(
    custom_agents=custom_agents,
    on_permission_request=PermissionHandler.approve_all,
)
```

## MCP servers

```python
mcp_servers = {
    "postgres": {
        "type": "stdio",
        "command": "pg-mcp",
        "args": ["--port", "5432"],
        "env": {"PGPASSWORD": "..."},
        "tools": ["*"],
    },
    "github": {
        "type": "http",
        "url": "https://api.githubcopilot.com/mcp/",
        "headers": {"Authorization": "Bearer ..."},
        "tools": ["*"],
    },
}

session = await client.create_session(mcp_servers=mcp_servers, ...)
```

## Hooks

```python
async def on_pre_tool_use(input, invocation):
    if input.tool_name == "bash" and "rm -rf" in input.arguments.get("command", ""):
        return {"permission_decision": "deny"}
    return None

async def on_user_prompt_submitted(input, invocation):
    return {"modified_prompt": f"[audit] {input.prompt}"}

session = await client.create_session(
    hooks={
        "on_pre_tool_use": on_pre_tool_use,
        "on_user_prompt_submitted": on_user_prompt_submitted,
    },
    on_permission_request=PermissionHandler.approve_all,
)
```

## User input handler

```python
async def on_user_input_request(request, invocation):
    # request: {"question": str, "choices": list[str] | None}
    if request.get("choices"):
        return {"answer": request["choices"][0], "wasFreeform": False}
    return {"answer": "yes", "wasFreeform": True}

session = await client.create_session(
    on_user_input_request=on_user_input_request,
    ...
)
```

## Permission handler

```python
async def on_permission_request(request, invocation):
    # request.kind: "shell" | "write" | "read" | "mcp" | ...
    if request.kind == "shell":
        if "dangerous" in request.command:
            return {"kind": "denied-by-policy"}
    return {"kind": "approved"}
```

Or use the built-in:

```python
from copilot import PermissionHandler
on_permission_request=PermissionHandler.approve_all
```

## Events

Two subscription styles:

### Async iterator (preferred)

```python
async for event in session.events():
    if event.type == "assistant.message":
        print(event.data.content)
    elif event.type == "tool.execution_complete":
        print(f"Tool done: {event.data.tool_call_id}")
    elif event.type == "session.idle":
        break
```

### Callback

```python
def handle_message(event):
    print(event.data.content)

session.on("assistant.message", handle_message)
```

## Python-specific advantages

1. **Context managers** — `async with CopilotClient() as client:` is clean
2. **Pydantic integration** — tool args validated automatically
3. **Typed dicts everywhere** — full IDE support with mypy / pyright
4. **Async/await native** — no wrapping needed
5. **GIL caveat** — heavy CPU work in tool handlers will serialize; for parallel agents, use multiple processes

## Testing

pytest-based. E2E tests in `/python/e2e/`:
- `test_mcp_and_agents.py`
- `test_permissions.py`
- `test_ask_user.py`
- `test_ui_elicitation.py`
- `test_session_lifecycle.py`
- etc.

## Build

```bash
just install-python
just format-python
just lint-python
just test-python
```

Or inside `/python/`:

```bash
pip install -e ".[dev]"
pytest
```

## See also

- [feature-parity-matrix.md](feature-parity-matrix.md)
- [../02-core-concepts/](../02-core-concepts/)

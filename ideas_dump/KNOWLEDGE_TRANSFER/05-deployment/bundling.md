# Bundling and Embedding the CLI

How to ship the Copilot CLI as part of your application.

## Why bundle?

- Zero configuration for end-users
- Deterministic CLI version (your app pins it)
- No network install step at first run
- Works in air-gapped environments (after initial bundle)

## Go bundler (the most interesting)

The Go SDK has a custom bundler that embeds the CLI binary via `go:embed` + Zstandard compression. This is unique — no other SDK ships this.

### Running the bundler

```bash
# From your Go project root
go run github.com/github/copilot-sdk/go/cmd/bundler@latest \
    -goos=linux -goarch=amd64 \
    -output=./embed
```

Creates `zcopilot_linux_amd64.go` alongside a compressed binary:

```
embed/
├── zcopilot_1.0.32_linux_amd64.zst   # compressed CLI
├── zcopilot_1.0.32_linux_amd64.license
└── zcopilot_linux_amd64.go           # generated Go file with go:embed directives
```

The generated file contains:

```go
//go:embed zcopilot_1.0.32_linux_amd64.zst
var embeddedCLI []byte

//go:embed zcopilot_1.0.32_linux_amd64.license
var embeddedLicense []byte

func init() {
    embeddedcli.Setup(embeddedcli.Config{
        Cli:     zstd.NewReader(bytes.NewReader(embeddedCLI)),
        CliHash: decodedHash,  // SHA-256 of decompressed binary
        Version: "1.0.32",
        License: embeddedLicense,
    })
}
```

### Using the embedded CLI

In your main:

```go
import _ "yourmodule/embed"   // triggers the init() above
// Now NewClient() will find the embedded CLI automatically
```

### Multi-platform builds

Run the bundler once per target platform:

```bash
for PLATFORM in "linux-amd64" "linux-arm64" "darwin-amd64" "darwin-arm64" "windows-amd64"; do
  IFS=- read GOOS GOARCH <<< "$PLATFORM"
  go run ./cmd/bundler -goos=$GOOS -goarch=$GOARCH -output=./embed
done
```

Each platform gets its own `.zst` file; Go's `//go:embed` + build tags handle the selection at compile time.

### Version detection

The bundler figures out which CLI version to bundle by:

1. Running `go list -m` to get the copilot-sdk version from your `go.mod`
2. Fetching `package-lock.json` from the SDK repo at that version
3. Extracting the `@github/copilot` CLI version from the lock file

So your CLI version is pinned to your SDK version automatically. To override:

```bash
go run ./cmd/bundler -cli-version=1.0.30 ...
```

### Compression (zstd)

Zstandard chosen over gzip for:
- Faster decompression (important for cold start)
- Better compression ratio for binaries
- Wide support

Compression ratios seen in practice: CLI goes from ~50 MB uncompressed to ~15-20 MB compressed.

### Runtime extraction

First run extracts the CLI to `~/.cache/copilot-sdk/copilot_<version>`:

```go
func (c *Config) Path() string {
    // sync.OnceValue — lazy, once-per-process
    return extractAndVerify()
}
```

- If the binary already exists at that path and SHA-256 matches, reuse it
- If hash mismatches, error (no automatic replacement)
- Uses `flock` to prevent concurrent processes extracting at the same time

### File locking (`go/internal/flock/`)

```go
flock.Acquire(filepath.Join(installDir, ".copilot-cli-1.0.32.lock"))
```

Prevents two processes from simultaneously extracting the CLI. Implementations:

- Unix: advisory POSIX locks (`syscall.Flock(LOCK_EX)`)
- Windows: mandatory kernel locks (`LockFileEx`)
- Unsupported platforms: proceeds without locking

### License files

The bundler also embeds the CLI's license. Extracted alongside the binary as `copilot_<version>.license`.

### Multi-version coexistence

Binary names include the version (`copilot_1.0.32`). So multiple versions can coexist in `~/.cache/copilot-sdk/` without conflict:

```
~/.cache/copilot-sdk/
├── copilot_1.0.30
├── copilot_1.0.30.license
├── copilot_1.0.32
├── copilot_1.0.32.license
└── .copilot-cli-1.0.32.lock
```

When you upgrade your SDK (and thus the bundled version), the old binaries stay until you clean them up. No automatic garbage collection.

## Bundling in other SDKs

### Node.js (`@github/copilot` npm peer dep)

The SDK depends on the `@github/copilot` npm package. `npm install` pulls it alongside the SDK. The CLI binary ships inside the npm package.

```json
{
  "dependencies": {
    "@github/copilot-sdk": "^0.2.2",
    "@github/copilot": "^1.0.32"
  }
}
```

### Python (`github-copilot` pip dep)

Similar to Node — pip installs the CLI alongside the SDK.

### .NET (NuGet RID bundle)

.NET packages CLI binaries per Runtime Identifier:

```
runtimes/
├── linux-x64/native/copilot
├── linux-arm64/native/copilot
├── osx-x64/native/copilot
├── osx-arm64/native/copilot
└── win-x64/native/copilot.exe
```

At runtime, the SDK looks in `runtimes/{current-rid}/native/copilot`.

### Java

Handled by the Maven artifact; details in the separate `github/copilot-sdk-java` repo.

## Override paths

Every SDK allows explicit path override:

### Node.js

```typescript
const client = new CopilotClient({ cliPath: "/usr/local/bin/copilot" });
```

### Python

```python
client = CopilotClient(cli_path="/usr/local/bin/copilot")
```

### Go

```go
client := copilot.NewClient(copilot.ClientOptions{
    CLIPath: "/usr/local/bin/copilot",
})
```

### .NET

```csharp
new CopilotClient(new CopilotClientOptions { CliPath = "/usr/local/bin/copilot" })
```

Or via environment:

```bash
export COPILOT_CLI_PATH=/usr/local/bin/copilot
```

## Air-gapped deploys

1. Bundle the CLI with your app (Go bundler, or npm/pip/NuGet offline cache)
2. Use `cliPath` or rely on the bundled one
3. Use BYOK with an air-gapped LLM (local Ollama, vLLM in-cluster)

No part of this SDK phones home independently — all network traffic is through the CLI's LLM provider endpoint.

## Windows-specific concerns

The Go SDK hides the console window on Windows (no black popup) via:

```go
cmd.SysProcAttr = &syscall.SysProcAttr{ HideWindow: true }
```

Other platforms need no special config.

## See also

- [deployment-patterns.md](deployment-patterns.md) — when to use each deployment mode
- [../07-internals/transport-and-protocol.md](../07-internals/transport-and-protocol.md) — JSON-RPC details
- [../03-sdk-comparison/go-sdk.md](../03-sdk-comparison/go-sdk.md) — Go SDK features

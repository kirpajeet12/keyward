# Keyward

**A vault Claude can use but never read.**

Stop pasting API keys, passwords and 2-step codes into AI chats. With Keyward, Claude asks for a secret and a secure dialog opens on your Mac. The secret is sealed by your Mac's **Secure Enclave**, and every use needs **your Touch ID**. Claude runs the command, and if the secret shows up in the output, Claude sees `«NAME»` instead.

```
You: deploy the site to AWS
Claude: I need your AWS keys. A Keyward dialog is opening…   ← you type them into a hidden Mac dialog
        [Touch ID: "Let Claude use AWS_KEY_ID, AWS_SECRET to run: aws s3 sync ./dist s3://…"]
        ✓ upload: dist/index.html   (AWS_SECRET → «AWS_SECRET» if it ever appears)
```

## Why it's different
- **Secure Enclave encryption:** secrets are sealed to a key that lives inside your Mac's security chip and can never leave it. Other apps, scripts and AI tools can't decrypt the vault, and a copied vault file is useless on another computer.
- **Touch ID for every use:** saving a secret needs nothing, but using one needs your fingerprint. The prompt shows exactly which secrets will be used and the command that will run. By default it's **fingerprint only**, with no password field. `keyward config password on` also allows your Mac password.
- **Claude can't read it:** the connector has no "read" tool. Keyward runs the command itself and blanks out secret values in the output, including base64 and URL-encoded copies.
- **2-step verification:** when a login asks for a code, Claude calls `keyward_request_code` and you type the current code into a dialog. It works once and expires after 5 minutes. Your authenticator stays with you.
- **Logins, keys and files:** API tokens, username + password pairs, and key files (`.p8`, `.pem`, service-account JSON) handed over as temporary files that are deleted right after use.
- **No third-party dependencies:** Apple's CryptoKit plus Python's standard library. One small Swift file and one Python file you can read in ten minutes.

## Install (Claude Code)
```
/plugin marketplace add kirpajeet12/keyward
/plugin install keyward@keyward
```
The first time it runs, Keyward compiles its Secure Enclave helper (needs the Xcode Command Line Tools: `xcode-select --install`).

To use it from a terminal too, add it to your PATH:
```
ln -s ~/.claude/plugins/marketplaces/keyward/bin/keyward ~/.local/bin/keyward
```

**Claude desktop app:** add this to `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{ "mcpServers": { "keyward": { "command": "/path/to/keyward/bin/keyward", "args": ["mcp"] } } }
```

## Commands
| Command | What it does |
|---|---|
| `keyward ask NAME [--type text\|login\|file] [--reason …]` | Secure dialog to add a secret |
| `keyward code NAME [--reason …]` | Ask for a 2-step code (single use, 5 minutes) |
| `keyward set NAME` | Type a secret in the terminal (hidden) |
| `keyward list` | Names and notes only, never values |
| `keyward run --with NAME[=VAR] -- cmd …` | Run with secrets after Touch ID; output masked |
| `keyward rm NAME` | Delete a secret |
| `keyward config password on\|off` | Also accept your Mac password (default: Touch ID only) |
| `keyward status` | Vault and Secure Enclave status |

Connector tools: `keyward_list`, `keyward_request_secret`, `keyward_request_code`, `keyward_run`, `keyward_remove`.

## How the encryption works
- `keyward init` creates a P-256 key inside the Secure Enclave with `privateKeyUsage + userPresence`. Only an opaque handle is stored on disk (`~/.keyward/enclave-key`), and it only works on this Mac's chip.
- Each secret is sealed separately: an ephemeral P-256 key does ECDH with the Enclave public key, HKDF-SHA256 derives an AES-256-GCM key, and the secret is encrypted with it. Sealing needs no authentication.
- Unsealing performs the ECDH inside the Secure Enclave after a LocalAuthentication check (Touch ID only by default). It runs inside a tiny background app, `~/.keyward/Keyward.app`, because macOS only shows the Touch ID sheet for apps. Your fingerprint never leaves the Secure Enclave; Keyward only learns yes or no.
- `~/.keyward/vault.json` holds only names, notes and ciphertext. It is `0600` in a `0700` folder.

## Honest limits
- Claude can't *read* the vault, but a command it writes could print a secret. That's why Touch ID shows the command first: read it before you approve. Masking catches secrets that appear as-is, base64 or URL-encoded, but not text the command transforms (such as `echo` turning `\b` into a backspace).
- macOS with a Secure Enclave (Apple silicon, or an Intel Mac with a T2 chip) is required. Touch ID-only mode needs Touch ID: a MacBook, or a Magic Keyboard with Touch ID on a Mac mini or Mac Studio.
- Claude Code's own Bash sandbox blocks Touch ID prompts, so use Keyward through its connector (or in your own terminal), not from sandboxed Bash commands.
- Anyone who can use your unlocked Mac *and* pass Touch ID or your Mac password can use the secrets. That person is you.

## Status and roadmap
Version 1.0 is new. The encryption, masking and connector are covered by automated tests; the Touch ID flow has been tested on one Mac so far. Please open an issue if something doesn't work on yours.

Coming next:
- **Sign in to websites:** Claude clicks the password box, you touch Touch ID, and Keyward types the password itself.
- **Approve from your iPhone,** for Claude running on its own computer.

## License
MIT

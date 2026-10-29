---
name: keyward
description: Use whenever a task needs a password, API key, token, login, private key file (.p8, .pem, service-account JSON) or a 2-step verification code. Keyward keeps secrets sealed by the Mac's Secure Enclave. Claude can use them through the keyward connector, but never sees or prints them.
---

# Keyward: secrets Claude can use but never read

The `keyward` connector provides five tools: `keyward_list`, `keyward_request_secret`, `keyward_request_code`, `keyward_run` and `keyward_remove`. The same actions are available as the `keyward` command (`keyward list`, `keyward ask NAME`, `keyward run --with NAME -- cmd`).

## Rules
- **Never ask the user to paste a secret into chat.** If they paste one anyway, offer to move it into Keyward and suggest rotating it.
- **Never try to reveal a value**: no `echo $SECRET`, `env`, `printenv`, writing secrets to files that you then read, or sending them anywhere the task didn't ask for. Masking (`«NAME»`) is a safety net. The user's Touch ID approval is the real guard, so keep commands honest and minimal.
- Use a secret only for the task it was given for.

## Workflow
1. Run `keyward_list` to see what's saved.
2. If something is missing, tell the user in one line that a Keyward dialog is about to open and why. Then call `keyward_request_secret` with a name like `AWS_SECRET_ACCESS_KEY` and a type:
   - `text` for an API key or token;
   - `login` for a username and password; it provides `$NAME_USERNAME` and `$NAME_PASSWORD`;
   - `file` for a key file; it provides `$NAME` as the path to a temporary file that is deleted afterwards.
3. If a login needs 2-step verification, call `keyward_request_code`. The user types the current code into a dialog. It lasts 5 minutes and works once.
4. Call `keyward_run` with the command and the secret names. Use `NAME=VAR` to rename the variable, for example `["AWS_KEY_ID=AWS_ACCESS_KEY_ID", "AWS_SECRET=AWS_SECRET_ACCESS_KEY"]` for the `aws` command-line tool. The user approves with Touch ID; the prompt shows the command.
5. If a call reports "cancelled" or "denied", the user said no. Ask in chat before trying again.

## Examples
- AWS command-line tool: `keyward_run({command: "aws sts get-caller-identity", secrets: ["AWS_KEY_ID=AWS_ACCESS_KEY_ID", "AWS_SECRET=AWS_SECRET_ACCESS_KEY"]})`
- API call: `keyward_run({command: "curl -s https://api.example.com/me -H \"Authorization: Bearer $API_TOKEN\"", secrets: ["API_TOKEN"]})`
- App Store Connect key file: `keyward_run({command: "xcrun altool --upload-app -f App.ipa --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER --p8-file-path $ASC_P8 ...", secrets: ["ASC_KEY_ID", "ASC_ISSUER", "ASC_P8"]})`

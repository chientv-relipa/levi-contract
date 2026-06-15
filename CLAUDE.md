## Context Loading Protocol

Before planning or implementing any features, load project documentation:

### Step 1 — Load Entry Point
Read `README.md` to get the project overview, the module map (`common/` · `states/` ·
`handlers/`), the Solana→Sui architecture mapping, and the build/test commands. If a
`docs/SUMMARY.md` exists later, read that too for the full documentation landscape.

The `Code Standard` section below is very important to keep the code consistent and
maintainable. Let documentation guide implementation — if docs conflict with
implementation needs, clarify with the user instead of guessing.

### Step 2 — Load on Demand
Based on the current task, open only the modules directly relevant:

- Authority / config changes → `sources/states/config.move`, `sources/states/capability.move`, `sources/handlers/initialize.move`, `sources/handlers/update_config.move`, `sources/handlers/update_maintenance.move`
- Agent lifecycle / reputation → `sources/states/agent.move`, `sources/handlers/register_agent.move`, `sources/handlers/activate_agent.move`, `sources/handlers/deactivate_agent.move`, `sources/handlers/update_agent_program_target.move`
- Action flow / verdict / escalation → `sources/states/action.move`, `sources/handlers/submit_action.move`, `sources/handlers/verdict_action.move`, `sources/handlers/approve_action.move`, `sources/handlers/reject_action.move`
- Lookup / events / constants → `sources/states/registry.move`, `sources/common/events.move`, `sources/common/constants.move`

Handlers follow **one module per instruction** (each named after its instruction, e.g.
`levi::submit_action::submit_action`), mirroring the Solana `contexts/` one-file-per-instruction layout.

The Sui/Move skill pack lives in `.agents/skills/sui-move/` — read it when you need Sui
object-model, capability, transaction, testing, or publishing patterns.

## Question Tool Mandate

`Question Tool` is the common method for asking users questions with interactive options.
Always use it when asking a question during task execution. Do not ask questions in plain
text unless the interface does not support interactive tools.

| Agent       | Tool                     |
| ----------- | ------------------------ |
| Claude Code | `AskUserQuestion`        |
| OpenCode    | `question`               |
| Gemini CLI  | `ask_user`               |
| Cursor      | `ask questions`          |
| Others      | Based on available tools |

Guidelines:

- Prefer selectable options (2–5 choices) over open-ended text when practical.
- Ask exactly one question per message; do not bundle multiple questions.
- Use open-ended plain-text questions only when the answer genuinely requires free-form input.
- Never interrupt the flow; the user should only have to respond to the question asked.

## General Principles

- Apply YAGNI, KISS, DRY, SOLID, and the principle of least surprise.
- Ask clarifying questions when documentation is unclear or critical context is missing.
- After any source change, run `sui move build` then `sui move test` and keep both green.
- Generate timestamps with inline bash commands:
  - Folder name: `` `date +%y%m%d-%H%M` ``
  - Document timestamp: `` `date "+%Y-%m-%d %H:%M:%S"` ``

## Code Standard (Move / Sui)

- **One module = one file.** To add files, split into more modules, not more files per module.
- **Constants (incl. error codes) are module-private.** There is no shared `errors`
  module — define each `#[error]` in the module that raises it. Use human-readable,
  specific messages.
- **Layering:** `states/` own the structs and expose `public(package)` operations +
  getters; `handlers/` are the entry functions (the "instructions") that orchestrate
  states. Do not access another module's struct fields directly — go through getters /
  package mutators.
- **Object sharing/transfer of a `key`-only object must happen in its defining module**
  (ability rule). That is why each state module owns a `create_and_share`.
- **Authority = capability objects** (`AdminCap`, `RelayerCap`) or `tx_context::sender`
  checks — never hardcoded addresses.
- **Maintenance gating:** call `config::assert_not_maintenance(config)` at the top of
  every mutating handler — `register_agent`, `submit_action`, `verdict_action`, and the
  agent lifecycle handlers (`deactivate`/`activate`/`update_target`). The only ungated
  mutators are escalation resolution (`approve_action` / `reject_action`), which mirror
  the Solana reference (Solana does not gate them either).
- **Events:** emit a granular event for every state transition via the `events` module.
- **Counters:** plain `+ 1` (Move aborts on overflow); saturate only where a cap is
  meaningful (e.g. `strikes` at `u8` max).
- Keep parity with the Solana reference (`../contract/`) for business rules; document any
  intentional divergence (e.g. `reject_action` adds a strike).

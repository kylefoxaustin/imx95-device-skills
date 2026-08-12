# agents/

This directory contains **agent workflow documents** — multi-step procedures that Claude
follows to accomplish complex, multi-skill tasks on the i.MX 95 board.

## Agents vs Skills

| | Skills | Agents |
|---|---|---|
| **Location** | `skills/<name>/` | `agents/<name>.md` |
| **Entry point** | `scripts/main.sh` | Markdown procedure document |
| **Execution** | Claude runs a script | Claude follows a written procedure, calling multiple skills |
| **Scope** | Single focused capability | Multi-step investigation or workflow |
| **State** | Stateless | Stateful — each step informs the next |

## How Claude Uses Agent Documents

1. Claude reads the agent `.md` file completely before starting.
2. The document defines a numbered sequence of steps.
3. Each step specifies which skill to invoke, what to look for in the output, and how to
   decide whether to continue, branch, or abort.
4. After all steps complete, Claude synthesizes findings into a final report.

Agent documents are **not scripts** — they are structured instructions for Claude's
reasoning process. They can include conditional logic ("if thermal throttling is detected,
skip to step 5"), thresholds, and report templates.

## Available Agents

| Agent | File | Purpose |
|-------|------|---------|
| `imx95-perf-investigator` | [`imx95-perf-investigator.md`](imx95-perf-investigator.md) | End-to-end performance investigation |

## Adding a New Agent

1. Create `agents/<name>.md`.
2. Start with a YAML front-matter block (same convention as SKILL.md).
3. Write numbered steps — each step must reference a specific skill or shell command.
4. Include a "Report Template" section at the end.
5. Update `README.md` skill table and `CLAUDE.md § 7`.

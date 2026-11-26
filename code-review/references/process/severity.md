# Severity

## Severity

Grade by harm, not by category.

| Severity | Meaning | Examples |
| --- | --- | --- |
| `blocker` | Would hurt in production, lose data, expose a secret, break availability, or violate a hard contract | Open ingress to a sensitive service; destructive replacement of a stateful resource; auth bypass; unsound `unsafe`; public API break |
| `important` | Real risk or contract violation that should be fixed, but not an immediate incident | Missing timeout; non-idempotent task that usually converges; weak test that would miss a regression; unbounded growth |
| `nit` | Optional improvement, or a real but low-impact issue | Naming, duplication, missing comment, theoretical edge case with negligible probability |

Style, formatting, import order, and lint violations are **not** review findings unless they violate an explicit repository rule that CI does not enforce. If CI enforces it, do not report it.

## Confidence

- `high`: proven by a caller trace, test, plan delta, or documented contract.
- `medium`: strong static evidence, but one assumption remains.
- `low`: plausible, not proven. Low confidence cannot be a blocker.

## Report shape

- **Blocking:** confirmed blockers only.
- **Important:** confirmed importants, including any finding whose corrected severity is important, such as a downgraded blocker.
- **Nits:** optional items, capped to the highest-value few.
- **Couldn't verify:** missing facts, one line each.

Every item needs an ID, lane, location, evidence, and suggested fix or next check.

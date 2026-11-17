# skreenrek specs: index

Specs for the factory (Manufacture, `.factory/project.conf`) live here, one branch and PR each. The factory picks the
first `Ready` row whose `Depends on` are all `Done`. Raph merges every PR (`AUTO_MERGE=0`).

There are no specs yet, so the factory has nothing to build.

| # | Spec | Status | Depends on | Agent run | Raph review |
|---|---|---|---|---|---|

Status values: `Draft` → `Ready` (Raph approved the spec) → `In progress` → `In review` → `Done`.
**Approval:** Raph merging a spec PR that sets `Status: Ready` is his approval of that spec.

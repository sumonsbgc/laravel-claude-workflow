# Plans index

Overview: `00-Overview.md`. Recon: `_recon.md` (existing apps). Status of every task: `/lw:plan-status`.

## Features in build order
| # | Folder | Purpose | Depends on | Wave | Owner |
|---|---|---|---|---|---|
| 00 | `00-foundation/` | | none | 0 | unassigned |
| 01 | `01-<feature>/` | | 00 | 1 | unassigned |

## Where to start
Foundation first and alone. Then every feature of a wave in parallel, one developer per feature folder. Inside a feature, lanes: data (02, 03), domain (04, 08), delivery (05, 06, 07), quality (09 to 12).

## Running a layer
```
/lw:task <feature> <layer>     for example /lw:task invoicing model
/lw:task <feature>             the feature's runnable layers in order
```

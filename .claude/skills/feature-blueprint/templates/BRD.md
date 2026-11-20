# BRD template (01-BRD.md)

The BRD is the first package and the only one without code. It is delivered as `01-BRD.pdf`, rendered from this markdown source (`01-BRD.md`) with the `anthropic-skills:pdf` skill; edit the `.md` and re-render, never edit the PDF. It is what the acceptance tests are traced back to, so every requirement is numbered `BR-01…`, written Given/When/Then, and testable. Write it for a developer who will never meet the stakeholder.

```markdown
# <Feature> — Business Requirements
Feature: <slug>   Layer: 01-BRD   Depends on: none
Owner: unassigned   Status: planned   Estimate: S

## 1. Problem
Two or three sentences: who hurts today, how, and what it costs.

## 2. Goals and non-goals
Goals
- G1 <measurable outcome>
Non-goals
- N1 <explicitly out of scope, so nobody builds it>

## 3. Actors
| Actor | Description | Can do |
|---|---|---|

## 4. User stories and acceptance criteria
### US-1 As a <actor> I want <capability> so that <benefit>
- BR-01 Given <state>, when <action>, then <observable result>
- BR-02 Given <unauthorised actor>, when <action>, then it is refused and nothing changes
- BR-03 Given <invalid input>, when <submit>, then <specific message> and nothing is saved

## 5. Business rules
| ID | Rule | Example |
|---|---|---|
| RULE-1 | An invoice number is unique per year and never reused | INV-2026-000123 |

## 6. Data
| Concept | Fields | Source of truth | Retention |
|---|---|---|---|

## 7. Permissions matrix
| Action | Guest | Owner | Staff | Admin |
|---|---|---|---|---|

## 8. Edge cases
Empty state, duplicate submit, concurrent edit, deleted parent, timezone boundary, maximum sizes, partial failure of an external call.

## 9. Non-functional requirements
| Area | Requirement |
|---|---|
| Volume | rows now / in 12 months |
| Latency | p95 for list and detail |
| Availability | |
| Audit | which changes are recorded and for how long |
| Privacy | personal data held, who can export or delete |
| Accessibility | WCAG 2.2 AA for new screens |

## 10. Assumptions
Decisions made without asking, each one reversible: "A1 Currency is single per invoice."

## 11. Open questions
| ID | Question | Default if unanswered | Owner |
|---|---|---|---|

## 12. Glossary

## 13. Traceability
| Requirement | Package that implements it | Test that proves it |
|---|---|---|
| BR-01 | 06-Controller | InvoiceTest::it_creates_an_invoice |
```

Fill the traceability table last, after `09-Test`. An acceptance criterion with no test is a gap in the plan.

Keep the BRD to the length the feature deserves: a CRUD admin page needs one page, a payments flow needs several.

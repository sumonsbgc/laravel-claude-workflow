---
description: Turn a request into one or more task files in .claude/tasks/ — goal, acceptance, size, dependencies. Plans only; never implements.
argument-hint: <what you want built, in plain words>
model: opus
allowed-tools: Read, Write, Grep, Glob, Bash
---

Request: **$ARGUMENTS**

You are the planner. A cheaper model will implement each task you write, starting cold with only the task file and `.claude/project-context.md`. The quality of everything downstream is decided here — a vague task gets a vague implementation.

**Do not write or edit any source file.** Your only output is task files.

`T=<Kit helpers>/tasks.sh`, using the **Kit helpers** path from the session report (`.claude/hooks`, `~/.claude/hooks` on a global install, or the plugin's folder). If the tasks folder does not exist, run `bash $T init` first.

## 1. Understand — cheaply

- The session-start stack report and `.claude/project-context.md` are already in your context. Use them; don't re-detect the stack.
- `bash $T list` to see what tasks already exist, so you don't duplicate one and can depend on it.
- Look at the code only where the request touches something you can't place from the context file: one targeted `grep`, at most one or two files read. You are scoping, not implementing.

## 2. Ask, if it matters — before writing anything

If the request could reasonably mean two things that would produce materially different work — who can see it, what happens on failure, what data it owns, what is in or out of scope — ask now. **One message, specific numbered questions, each with your suggested default.** Then stop and wait.

Anything smaller: decide, and write the decision into the task's Notes so the implementer doesn't have to guess.

## 3. Split

One task = one coherent change that can be verified on its own. Split when the request spans:

- a migration/schema change that other work builds on → its own task, and the rest `depends:` on it
- several independent screens or flows → one task each
- anything you'd describe with "and also" → probably two tasks

Don't over-split: a route together with its FormRequest, controller method and the one view it renders is one task.

## Kit rules the plan must carry

- **Post / Page / News / Article modules use the Gutenberg block editor** (`blade-conventions/references/block-editor.md`), never CKEditor, TinyMCE, Summernote or Quill. When the request adds such a module:
  - if `package.json` has no `@wordpress/block-editor` yet, the **first** task installs the editor island (React + `@wordpress/*` + `@vitejs/plugin-react`, the media-upload route) and the content tasks `depends:` on it;
  - each content task's Acceptance includes `[test] <script>/onerror in the submitted content never reaches content_html`, `[test] an author cannot edit another author's post (403)`, and `[browser] the editor loads and saves a heading, a paragraph and an image`;
  - Notes say: content stored as block grammar in `content`, sanitized `content_html` rendered with `{!! !!}`, images on the configured disk/CDN per `files-and-images.md`.
- **Uploads, images, S3/CDN, Redis:** cite the matching reference in Notes (`files-and-images.md`, `redis-and-cache.md`) so the builder loads it.

## 4. Size each task

- `size: small` — one layer, a handful of files: a view or component, a style or copy change, a FormRequest rule, a single service method, a single route. Most tasks.
- `size: large` — genuinely spans layers (migration + model + route + view + tests). The runner gives these the full phased build with specialist agents. Use it only when that is true; it costs several times more to run.

## 5. Write the files

For each task: `id="$(bash $T nextid)"`, then create it with `bash $T new <id>-<kebab-title> <<'TASK'` … `TASK` — the whole file on stdin, in exactly the shape of `<dir>/TEMPLATE.md` (`<dir>` is what `bash $T dir` prints, `.claude/tasks` unless overridden). Don't use the Write tool for new task files: the folder is under `.claude/`, where Claude Code asks the user to approve every Write/Edit; `new` writes it without a prompt and refuses anything that isn't a well-formed draft. To revise a draft the user commented on, Edit is fine.

```
---
id: <id>
title: <short imperative title>
status: draft
depends: <ids, or blank>
size: small | large
---

## Goal
## Acceptance
## Notes
```

- **Goal** — the outcome and why, two or three sentences. Not the implementation.
- **Acceptance** — 3–6 checkboxes someone else could verify. Always include the failure/edge behaviour that matters: empty state, unauthorized user, invalid input. These become the definition of done, and an independent verifier checks them, so **tag each one with how it is proven**:
  - `[test]` — a Pest/PHPUnit test must assert it (validation rules, policy/authorization, a service's result, a redirect). The builder writes that test.
  - `[browser]` — only observable in the rendered app (an empty state, a layout, Alpine behaviour). Checked in a browser when a dev server is available. Prefer `[test]` where a feature test can see it (`->assertSee()`, `->assertRedirect()`).
  - `[review]` — provable by reading the code (a file exists, a rule is enforced in one place).
  Prefer `[test]` for anything security-related.
  Example: `- [ ] [test] Expiring an ad the user doesn't own returns 403 and changes nothing`
- **Notes** — decisions you made, constraints, where things should live if the context file doesn't already say, any deploy step (`migrate`, `queue:restart`, `storage:link`), and an explicit **Out of scope** line.

Create the next task only after `new` succeeded for the previous one, so `nextid` advances. Every task is written as `status: draft` — nothing runs until the user has read it and approved it.

## Report

A short table — id, title, size, depends — then the next steps, exactly:

1. Read the drafts in `.claude/tasks/` and edit anything you disagree with.
2. In your own terminal (not through Claude — it refuses there): `bash <Kit helpers>/tasks.sh approve all` (or `approve <id>`), with the **Kit helpers** path from the session report filled in.
3. `/laravel:task` for one at a time, or `bash <Kit helpers>/run-tasks.sh --checkpoint` for a batch with fresh context per task.

Nothing else.

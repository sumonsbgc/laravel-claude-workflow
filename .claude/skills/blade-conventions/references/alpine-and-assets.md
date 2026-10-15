# Alpine.js and assets in a Blade project

## Getting server data into JavaScript

Blade escapes for HTML. A `<script>` block is not HTML content, so `{{ }}` is the wrong tool there — a value containing a quote breaks the script, and a value containing `</script>` ends it early.

```blade
{{-- wrong: HTML-escaped into a JS context --}}
<div x-data="{ items: {{ $items }} }">
<script>const user = {{ $user }};</script>

{{-- right --}}
<div x-data="{ items: @js($items) }">
<script>const user = @js($user);</script>

{{-- also right: JSON in a data attribute, read by Alpine --}}
<div data-items="{{ json_encode($items) }}" x-data="gallery($el.dataset.items)">
```

`@js()` is `json_encode` with the flags that make the result safe to embed in a script or an attribute. Use it every time.

## Alpine patterns that stay maintainable

Inline `x-data` is fine for a toggle. Past a few lines, register a component in your JS entry and reference it by name:

```js
// resources/js/admin.js
import Alpine from 'alpinejs'

Alpine.data('newsFilters', (initial) => ({
    query: initial.query ?? '',
    open: false,
    get isFiltered() { return this.query !== '' },
    submit() { this.$refs.form.submit() },
}))

window.Alpine = Alpine
Alpine.start()
```

```blade
<div x-data="newsFilters(@js(['query' => request('q')]))" x-cloak>
    <input x-model="query" @keydown.enter="submit()">
    <span x-show="isFiltered">filtered</span>
</div>
```

- **`x-cloak`** on anything that would flash unstyled before Alpine boots, with `[x-cloak] { display: none }` in your CSS. Without it, every collapsed panel appears open for one frame.
- `x-show` keeps the element in the DOM (cheap toggling); `x-if` (inside `<template>`) removes it (use when the content is expensive or must not exist).
- `x-model` for two-way binding, `@click`/`x-on:click` for events, `$refs` instead of `document.querySelector`.
- **Alpine is presentation state.** Anything that must survive a reload belongs in the URL (a query string the controller reads) or the database — not in `x-data`.
- Keyboard reality check: a `@click` on a `<div>` is not reachable by keyboard. Use a `<button>`, or add `tabindex="0"` **and** `@keydown.enter`/`@keydown.space`.
- `x-transition` respects nothing by default — wrap motion in a `@media (prefers-reduced-motion: reduce)` rule that disables it.

## Vite

```blade
@vite(['resources/css/admin.css', 'resources/js/admin.js'])
```

- Never hand-write `<script src="/build/...">`. The filename is hashed per build; only `@vite` reads the manifest, and only `@vite` connects to the dev server for hot reload.
- Entry points are declared in `vite.config.js`. A project with separate admin and frontend bundles has separate entries — put a new file in the right one, and don't import admin JS into the public page.
- Images referenced from CSS/JS are processed by Vite; images referenced from Blade use `asset('images/x.png')` out of `public/`.
- `npm run dev` serves the assets; `npm run build` writes `public/build`. A page that looks unstyled in production usually means the build did not run, or `@vite` was replaced with a literal path.
- Third-party JS from a CDN belongs in the layout with `@once` around it, or as a dependency in `package.json` — not pasted into three views.

## Where JavaScript belongs

| Scope | Put it |
|---|---|
| a two-line toggle used once | inline `x-data` in the component |
| behaviour shared by several views | `Alpine.data(...)` in the entry point |
| anything with real logic (canvas, drag, a parser) | its own module under `resources/js/`, imported by the entry |
| a value the server knows | `@js()` into the component, never re-fetched over an endpoint you invented for it |

Inline `<script>` blocks scattered through views are how a Blade app ends up with three copies of the same handler and no way to test any of them.

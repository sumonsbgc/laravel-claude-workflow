# Styling a Blade project

Check the stack report first: it names the installed CSS framework and version. If Tailwind is not installed, do not write Tailwind classes — match whatever the project uses.

## Tailwind v4 vs v3 — they are configured differently

**v4** (`tailwindcss@4`, usually with `@tailwindcss/vite`):

```css
/* resources/css/app.css */
@import "tailwindcss";

@theme {
    --color-brand: oklch(0.62 0.19 250);
    --font-display: "Hind Siliguri", sans-serif;
}

@layer base {
    button, [role="button"], a { cursor: pointer; }
    [x-cloak] { display: none !important; }
}
```

- No `tailwind.config.js` by default — theme values live in `@theme` in the CSS. If the repo still has a config file, v4 ignores it unless the CSS says `@config "../../tailwind.config.js";`.
- Content sources are auto-detected; `@source "../views";` adds a path the scanner would otherwise miss (a package's Blade files, for instance).
- `@tailwind base/components/utilities` is v3 syntax and compiles to nothing in v4.

**v3** (`tailwind.config.js` with a `content` array): the config file is authoritative, and `content` **must** list `./resources/views/**/*.blade.php` or nothing in your views is generated.

## Utilities that changed in v4

| v3 | v4 |
|---|---|
| `bg-opacity-50` | `bg-black/50` |
| `flex-shrink-0` / `flex-grow` | `shrink-0` / `grow` |
| `overflow-ellipsis` | `text-ellipsis` |
| `decoration-slice` | `box-decoration-slice` |
| `outline-none` (no ring) | `outline-hidden` — in v4, `outline-none` really means `outline: none` |

Write for the **installed** version: `node -p "require('tailwindcss/package.json').version"`. A utility from a newer minor emits no CSS and no error — the element just renders unstyled.

## The pointer cursor

v4's Preflight no longer sets `cursor: pointer` on buttons. Every button in the app looks non-interactive until someone adds it. Fix it once in the base layer (see the CSS above) rather than remembering `cursor-pointer` on every element — and add `disabled:cursor-not-allowed` where a control can be disabled.

## Class names must exist in the source

Tailwind scans source text. It never evaluates PHP, so:

```blade
{{-- generates nothing --}}
<div class="bg-{{ $color }}-500">
<div class="{{ 'text-' . $size }}">

{{-- fine: the whole class is in the source --}}
<div class="{{ $active ? 'bg-blue-600' : 'bg-gray-200' }}">
<div @class(['rounded p-2', 'bg-red-100' => $hasError])>
```

Map a value to complete class strings:

```php
$badge = match ($news->status) {
    'published' => 'bg-green-100 text-green-800',
    'draft'     => 'bg-yellow-100 text-yellow-800',
    default     => 'bg-gray-100 text-gray-700',
};
```

Put that in an accessor or a helper, not in an `@php` block.

## Keeping it consistent

- Repeated class strings are a component, not a copy-paste. `<x-button>`, `<x-card>`, `<x-form.input>`.
- Theme tokens (`text-brand`, `bg-surface`) over arbitrary values (`text-[#1a73e8]`). One arbitrary value is fine; a palette of them is a design system nobody can change.
- A shared admin table, form field and button component removes more duplication than any other refactor in a Blade admin panel.
- Dark mode, if the project has it, is a `dark:` variant on the tokens — not a second stylesheet.
- Respect `prefers-reduced-motion` on anything that animates.

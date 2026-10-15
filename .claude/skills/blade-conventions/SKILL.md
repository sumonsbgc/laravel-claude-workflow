---
name: blade-conventions
description: What may live in a .blade.php file and where the rest belongs — components, slots and attributes, forms and validation display, Alpine.js, Vite assets, and Tailwind in a Blade project. Load before writing, reviewing or refactoring any view, component, or view composer.
---

# Blade conventions

## The one rule everything else follows from

**A view renders data it was given. It does not fetch, decide, or compute.**

By the time Blade runs, the controller has finished. Every query in a template is a query nobody batched, every branch is logic nobody can test, and every `@php` block is code hiding where no static analysis will look.

So a `.blade.php` file may contain: markup, `{{ }}` output, presentational conditionals (`@if ($news->isPublished())`), loops over data it was handed, includes and components, and `@can` checks that hide UI whose real enforcement is server-side.

It may **not** contain: `Model::where(...)`, `DB::`, `env()`, a multi-line `@php` block, business rules, or formatting logic duplicated across three files.

## Where the logic goes instead

| The view needs | Put it in |
|---|---|
| data for one route | the controller, passed to `view('x', [...])` |
| data for *every* render of a view or partial (nav counts, ads, settings) | a **view composer** in `app/View/Composers`, bound in a service provider |
| a derived value from one model (`$news->formattedDate`) | an **accessor** on the model |
| a formatting rule used in several views (Bangla digits, money, a status label) | a **helper function** or a small formatter class |
| a chunk of markup used more than once | a **Blade component** |
| a screen's worth of presentation decisions | a **view model** — a plain class the controller builds and the view reads |
| interaction | Alpine, in the component that owns the markup |

A view composer is the tool people forget:

```php
// app/Providers/AppServiceProvider.php
View::composer(['frontend.front', 'components.frontend.*'], AdComposer::class);
```

Now every one of those views has `$ads` without a single controller repeating itself.

## Components over includes

`@include` shares markup but not a contract — it silently inherits every variable in scope, so renaming a controller variable breaks partials you did not know existed. A component declares what it takes.

```blade
{{-- resources/views/components/card.blade.php --}}
@props(['title', 'href' => null, 'muted' => false])

<article {{ $attributes->merge(['class' => 'rounded-lg border p-4']) }}>
    <h3 @class(['font-semibold', 'text-gray-500' => $muted])>{{ $title }}</h3>
    {{ $slot }}
    @isset($footer)
        <footer class="mt-3 text-sm">{{ $footer }}</footer>
    @endisset
</article>
```

```blade
<x-card title="Front page" :href="route('admin.news.index')">
    Body content
    <x-slot:footer>12 items</x-slot:footer>
</x-card>
```

- **Anonymous components** (a file in `resources/views/components/`) for markup. **Class components** (`app/View/Components/`) only when the component needs data or logic of its own.
- `@props` declares every input with its default. Anything not in `@props` lands in `$attributes` and is spread onto the root element by `$attributes->merge(...)` — that is what keeps `class`, `id`, `wire:model` and `x-on:click` working from the call site.
- Pass values with `:name="$expr"` and strings with `name="literal"`.
- One component, one job. A component with eight booleans is several components.

## Escaping — the security boundary

- `{{ $value }}` escapes. This is the default and it is correct.
- `{!! $value !!}` does not. Use it only for HTML that was authored by a trusted editor **and** sanitized on write. Never for anything derived from the request.
- Inside `<script>`, Blade's HTML escaping is the wrong escaping: `@js($value)` produces valid JavaScript. `{{ $json }}` in a script tag breaks on a quote and is exploitable via `</script>`.
- Inside an attribute, `{{ }}` is fine; inside an `href`, validate the scheme — `{{ $url }}` will happily print `javascript:...`.

## References

- `references/components.md` — component patterns, slots, attribute bags, layouts, and when to reach for a view model.
- `references/block-editor.md` — **Post/Page content uses the Gutenberg block editor** (kit rule, never CKEditor/TinyMCE): the `@wordpress/block-editor` React island, storage as block grammar, sanitized `content_html`, media uploads, required tests.
- `references/forms.md` — forms, CSRF, `old()`, error display, and the accessible markup that goes with them.
- `references/alpine-and-assets.md` — Alpine patterns that survive Blade escaping, `@vite`, and where JS belongs.
- `references/styling.md` — Tailwind v3 vs v4 in a Blade/Vite project, class scanning, and the pointer-cursor rule.

## Related

- `laravel-conventions` — the controller, composer, service and model layers this file's rules push work into.
- `php-conventions` — for the PHP inside class components and view models.

## Verification

Render the route. A Blade error is reported against the *compiled* file, with a line number that does not exist in your source — so an unbalanced `@if`/`@endif` is easier to spot by reading than by trusting the error. `php artisan view:clear` after changing a component's name or namespace; stale compiled views are a real source of "my change did nothing".

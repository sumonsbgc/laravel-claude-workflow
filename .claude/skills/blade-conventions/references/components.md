# Components, slots, layouts and view models

## Anonymous vs class components

**Anonymous** — a file in `resources/views/components/`. No PHP class, no registration. This is the default and covers most cases.

```
resources/views/components/badge.blade.php   ->  <x-badge>
resources/views/components/admin/table.blade.php -> <x-admin.table>
```

**Class** — `app/View/Components/` plus its view. Reach for one only when the component must query, compute, or resolve something from the container:

```php
class NewsStatusBadge extends Component
{
    public function __construct(public News $news) {}

    public function label(): string
    {
        return match ($this->news->news_status) {
            News::PUBLISHED => 'Published',
            News::DRAFT     => 'Draft',
            default         => 'Unknown',
        };
    }

    public function render(): View { return view('components.news-status-badge'); }
}
```

Everything public on the class is available in the view. A class component that only passes props through should have been anonymous.

## Props and the attribute bag

```blade
@props([
    'variant' => 'primary',      // with a default
    'href',                      // required — omitting it is an error at render
])

<a href="{{ $href }}"
   {{ $attributes->class([
        'inline-flex items-center rounded px-3 py-2 cursor-pointer',
        'bg-blue-600 text-white'   => $variant === 'primary',
        'bg-gray-100 text-gray-900' => $variant === 'secondary',
   ]) }}>
    {{ $slot }}
</a>
```

- `$attributes->merge(['class' => '...'])` appends the caller's classes; `->class([...])` merges conditionals; `->except('foo')` drops one.
- Without an `$attributes` spread on the root element, `class`, `id`, `x-data` and `wire:*` passed at the call site are silently discarded.
- `@aware(['theme'])` reads a prop from the parent component when a child needs it and you do not want to thread it manually.

## Slots

```blade
<x-modal>
    <x-slot:title>Delete news</x-slot:title>
    Are you sure?
    <x-slot:actions>
        <x-button type="submit">Delete</x-button>
    </x-slot:actions>
</x-modal>
```

Inside the component, `{{ $slot }}` is the default content and `{{ $title }}` / `{{ $actions }}` are the named ones — guard optional slots with `@isset($footer)`. Slots beat boolean props: `<x-modal :has-footer="true" footer-text="…">` is a component asking to be given markup instead.

## Layouts

Two idioms; use whichever the repo already uses, and don't mix them in one view.

**Component layout** (preferred in new code):

```blade
{{-- resources/views/components/layouts/admin.blade.php --}}
<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $title ?? config('app.name') }}</title>
    @vite(['resources/css/admin.css', 'resources/js/admin.js'])
    @stack('head')
</head>
<body class="min-h-screen bg-gray-50">
    <x-admin.sidebar />
    <main class="p-6">{{ $slot }}</main>
    @stack('scripts')
</body>
</html>
```

```blade
<x-layouts.admin title="News">
    ...
</x-layouts.admin>
```

**Template inheritance** (`@extends` / `@section` / `@yield`) — still fine, and what most existing admin panels use. Match the file you are editing.

`@push('scripts')` / `@stack('scripts')` is how a view contributes a script to the layout. `@once` around anything that must appear only one time even if the component renders in a loop.

## View models

When a screen needs six variables and three of them are derived, the controller starts computing presentation. Give it a class instead:

```php
final readonly class EditionPage
{
    public function __construct(public Collection $pages, public string $heading, public ?string $prevUrl) {}

    public static function for(Carbon $date, Collection $news): self { ... }
}
```

The controller builds it, the view reads `$page->heading`. Testable, and no `@php` in the template.

## Performance

- `@include` inside a loop compiles and renders a whole view per iteration. For anything more than a few rows, inline the markup or use a component.
- Pass already-loaded relations. A view that touches `$item->category` on a collection loaded without `with('category')` is an N+1 that looks like a rendering problem.
- `@fragment` + `->fragment('name')` returns just one piece of a view — useful for partial updates without an API.
- `php artisan view:cache` in production; `view:clear` locally when a component rename appears to have done nothing.

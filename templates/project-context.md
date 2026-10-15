# Project context

<!--
  Maintained by the laravel-workflow. Facts about THIS codebase that are expensive to rediscover:
  where things live, what they are called, decisions already made.

  Rules: one line per fact. No history, no narrative, no restating what the code obviously says.
  Keep the whole file under ~60 lines — when it grows past that, merge and prune rather than append.
  This file is injected at the start of every session, so every line costs tokens forever.
-->

## Layout

<!-- e.g. admin controllers: app/Http/Controllers/Admin/<Model>Controller.php, requests in app/Http/Requests/Admin/ -->
<!-- e.g. views: resources/views/admin/<resource>/{index,create,edit}.blade.php, layout via @extends('admin.layout') -->

## Conventions

<!-- e.g. authorization: permission:<resource>.<action> middleware + $user->hasPermission() -->
<!-- e.g. cache invalidation: ClearsCache trait on the model, keys listed in CacheService -->
<!-- e.g. dates shown to users go through rupantor($date)->full() -->

## Decisions

<!-- e.g. 2026-09-03 — new screens use <x-...> components, not @include partials -->

## Gotchas

<!-- e.g. the frontend edition date comes from option('today_date'), not from now() -->

# Authentication and authorization

## Where the check belongs

Three layers, each answering a different question. A real app uses all three:

| Layer | Question | Example |
|---|---|---|
| Middleware | may this request reach this route at all? | `auth`, `verified`, `admin.access` |
| Policy / gate | may **this user** act on **this record**? | `$user->can('update', $news)` |
| Validation | is the payload well-formed, and are the referenced ids real? | `exists:categories,id` |

The one that gets skipped is the middle one. Route middleware saying "an editor may edit news" does not say "this editor may edit *this* news item" — without the per-object check, changing the id in the URL edits someone else's row.

## Policies

```php
class NewsPolicy
{
    public function update(User $user, News $news): bool
    {
        return $user->hasPermission('news.edit')
            && ($user->hasPermission('news.edit.any') || $news->created_by === $user->id);
    }
}
```

- Policies are auto-discovered for `App\Models\X` → `App\Policies\XPolicy`. Otherwise register them with `Gate::policy()` in a provider.
- Call them from the FormRequest (`$this->user()->can('update', $this->route('news'))`), from the controller (`$this->authorize('update', $news)`), or on the route (`->can('update', 'news')`).
- `Gate::before(fn ($user) => $user->isSuperAdmin() ?: null)` for the one global override. Return `null`, not `false`, or you deny everything else.
- In Blade: `@can('update', $news) … @endcan`. Hiding a button is presentation, not enforcement — the server-side check still has to exist.

## Hand-rolled RBAC

Plenty of projects have their own `roles` / `permissions` / pivot tables instead of a package. When that is what the repo has, extend it — do not install `spatie/laravel-permission` alongside it.

- Keep the matching key in one place (a `key` column, an enum, or constants). Permission strings scattered as literals across controllers drift.
- Cache the resolved permission set per user for the request; recomputing it on every `hasPermission()` call is a query per check.
- Bust that cache when roles or permissions change — an observer on the pivot writes is the usual place.
- A `super_admin` short-circuit belongs in exactly one method.

## Authentication

- `auth()->user()`, `$request->user()`, `Auth::user()` are the same thing. Pick the one the codebase already uses.
- `auth()->id()` rather than `auth()->user()->id` — no null dereference when the session has expired.
- Guards separate audiences (`web`, `admin`, `api`); check `config/auth.php` before assuming there is only one.
- Never trust a role or id from the request body. Read it from the authenticated user.
- Password fields: `Hash::make()` on write (or a `'hashed'` cast on the model), `Hash::check()` on compare. Never `md5`/`sha1`/`bcrypt()` by hand.
- Rate-limit the login route (`throttle:5,1`) and anything that sends mail or SMS.

## Common holes

- A route group where one route was added outside the `->middleware()` closure.
- `authorize()` in a FormRequest returning `true` with no route middleware behind it.
- An id, price, status, or `user_id` accepted from the request and written straight to the model.
- A mass-update endpoint (`POST /news/bulk-publish`) that checks the permission but not the ownership of each id in the array.
- API tokens or signed URLs with no expiry.
- `@can` in the view as the only guard, with no check in the controller.

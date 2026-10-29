---
name: php-conventions
description: General PHP conventions for this codebase — naming, class and function design, types, control flow, exceptions, collections, imports, comments and dead code. Load before writing or reviewing any PHP file, alongside laravel-conventions.
---

# PHP conventions

Formatting is Pint's job — never hand-format, never argue with it, and never add a style rule to a file. These are the decisions Pint cannot make for you.

## Naming

- `PascalCase` classes, `camelCase` methods and variables, `SCREAMING_SNAKE` constants, `snake_case` database columns and array keys that mirror them.
- Class names say what the thing **is**: `NewsPublisher`, not `NewsHelper` or `NewsManager`. "Manager", "Helper", "Util" and "Data" are names for boxes nobody can close.
- Methods say what they **do** and return: `publish()`, `hasPermission()`, `toArray()`. Booleans read as predicates — `isPublished()`, `canEdit()`, `hasChildren()`.
- One class per file, named after the file. Suffixes follow the layer: `*Controller`, `*Request`, `*Policy`, `*Observer`, `*Service`, `*Job`.
- Don't abbreviate: `$category` not `$cat`, `$request` not `$req`. `$i` in a loop is fine.

## Types

Type everything: parameters, returns, properties. Untyped PHP is where the null gets in.

```php
public function publish(News $news, User $actor, ?Carbon $at = null): News
private array $keys = [];
public function __construct(private readonly CacheService $cache) {}
```

- `?Type` for genuinely optional, `Type|null` never as a shrug — decide whether null is meaningful.
- `iterable`/`Collection` over bare `array` when the shape matters; a docblock `@param array<int, News>` where generics would help a reader.
- **Enums** for a fixed set of values: `enum NewsStatus: int { case Draft = 2; case Published = 1; }` beats class constants and beats magic integers everywhere.
- `readonly` for value objects and constructor-promoted dependencies.
- `declare(strict_types=1)` only if the file's neighbours have it — consistency beats correctness-in-one-file here.

## Functions and methods

- One job. If you need "and" to describe it, it is two methods.
- Under ~30 lines. Past that, extract a private method with a name that explains the extracted part.
- Four parameters is a lot; five means a data object or a DTO.
- **Guard clauses over nesting.** Return or throw early; keep the happy path at the left margin.
- No boolean parameters that switch behaviour (`->save($andPublish = true)`). Two methods.
- Return one type. `int|false|null` forces every caller to write the same three branches.

## Control flow

- `match (true)` over long `if/elseif` ladders; `match` over `switch` (strict comparison, no fallthrough, it is an expression).
- `??` and `?->` instead of `isset()` pyramids — but `?->` on something that should never be null hides the bug.
- `===` always. `==` in PHP has surprises you do not want to relearn.
- Named arguments where a call site is otherwise unreadable: `->paginate(perPage: 20, page: $page)`.

## Collections

Laravel's `Collection` replaces most loops, and reads better when the chain is short:

```php
$byPage = $news->groupBy('page_no')->map(fn ($items) => $items->sortBy('position'));
```

- Chains of more than four operations are usually clearer as a loop with a name.
- `first()`, `firstOrFail()`, `sole()` — `sole()` when exactly one match is the invariant, because it throws when that is violated instead of quietly taking one.
- Don't `->toArray()` and back; stay in the collection.
- `->each()` for side effects, `->map()` for values. Using `map` for side effects hides them.

## Exceptions

- Throw a **specific** exception, catch a specific exception. `catch (\Exception $e)` around a block of five statements means you no longer know which one failed.
- Never swallow: an empty catch, or a catch that only logs and continues with corrupt state, turns a crash into a data bug.
- Domain failures get domain exceptions (`EditionNotImportable`), rendered by the exception handler into the right status.
- `report($e)` to log and continue deliberately; `throw` to stop. Choose one on purpose.
- No `@` error suppression. Ever.

See `references/errors-and-exceptions.md` for the shapes.

## Imports and structure

- `use` every class; no inline `\App\Models\News::` in the body. Facades are imported too.
- No unused imports (Pint removes them; check that it ran).
- Group related classes into a namespace that matches the directory, PSR-4.
- Helper functions live in a file autoloaded via `composer.json` `autoload.files` — and must be in `autoload`, not `autoload-dev`, or `composer install --no-dev` breaks production.

## No comments, no dead code

- **The code you write carries no comments.** No `//`, `#` or `/* */` in PHP, no prose docblocks, no `{{-- --}}` or `<!-- -->` in Blade, none in JS or CSS. Pure code: say the intent through names, types, enums and small methods. A comment that feels necessary means the code wants a better name or one more method.
- Allowed, because tooling needs them: type-only docblock tags PHP cannot express (`@param array<string, News[]>`, `@return HasMany<Post, $this>`, `@property`, `@throws`), `@phpstan-ignore` (give the reason in your report, not in the code), and license headers that already exist.
- Comments already in a file stay as they are; don't add new ones beside them.
- The `//` notes in this skill's and its references' examples are explanations for you. Never copy them into code.
- Delete dead code instead of commenting it out — git remembers.
- No `TODO`s: finish it, or record the rest as a new task.
- `guard-comments.sh` blocks an Edit/Write that adds a comment, before the file is written (`LARAVEL_WF_COMMENT_GUARD=off` is the user's switch).

## References

- `references/types-and-structure.md` — classes, DTOs, enums, dependency injection, static analysis.
- `references/errors-and-exceptions.md` — exception shapes, logging, external calls, transactions.

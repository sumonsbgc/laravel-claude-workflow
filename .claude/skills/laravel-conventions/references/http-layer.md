# The HTTP layer

## Routes

```php
// routes/web.php — grouped, named, thin
Route::middleware(['auth', 'admin.access'])->prefix('admin')->name('admin.')->group(function () {
    Route::resource('news', NewsController::class);
    Route::post('news/{news}/publish', [NewsController::class, 'publish'])
        ->middleware('permission:news.publish')
        ->name('news.publish');
});
```

- **Controller arrays, never closures.** `route:cache` fails on a closure route, so one closure disables route caching for the whole app.
- **Name every route** and link with `route('admin.news.edit', $news)`. A hardcoded `/admin/news/…` breaks silently when a prefix changes.
- Extra route files are registered in `bootstrap/app.php`:
  ```php
  ->withRouting(
      web: __DIR__.'/../routes/web.php',
      commands: __DIR__.'/../routes/console.php',
      then: fn () => Route::middleware('web')->group(base_path('routes/admin.php')),
  )
  ```
- Verify with `php artisan route:list --path=news` rather than guessing at the URL or the name.

## Route model binding

`Route::get('news/{news}', ...)` + `public function show(News $news)` resolves and 404s for you. Use it instead of `News::findOrFail($id)`.

- Bind on a different column: `Route::get('news/{news:slug}', ...)`, or `getRouteKeyName()` on the model.
- Scope a nested binding so the child must belong to the parent: `->scopeBindings()` on the route or group. Without it, `/categories/1/news/999` happily loads news 999 from another category.
- `->missing(fn () => redirect()->route('admin.news.index'))` when a 404 page is the wrong answer.

## FormRequests

One per action that accepts input. It holds both halves of "should this be allowed and is it well-formed":

```php
class StoreNewsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', News::class);
    }

    public function rules(): array
    {
        return [
            'title'       => ['required', 'string', 'max:255'],
            'page_no'     => ['required', 'integer', 'min:1'],
            'category_id' => ['required', 'exists:categories,id'],
            'image'       => ['nullable', 'image', 'mimes:jpg,png,webp', 'max:4096'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $this->merge(['slug' => str($this->title)->slug()]);
    }
}
```

- `$request->validated()` is the only thing that reaches a model write.
- Array rules (`['required', 'string']`) over pipe strings — they survive rules containing a `|`, like a regex.
- `exists:` / `unique:` do the lookup for you; don't re-check in the controller.
- File inputs need `mimes:` **and** `max:` before anything is stored.
- `authorize()` returning `true` is only correct when the route's middleware already performs the full check, including per-object ownership.

## Controllers

```php
public function store(StoreNewsRequest $request, NewsService $news): RedirectResponse
{
    $created = $news->publish($request->validated(), $request->user());

    return to_route('admin.news.show', $created)->with('status', 'News published.');
}
```

- Resource controllers use the seven standard names (`index show create store edit update destroy`). Anything else is a separate single-action controller (`__invoke`) or a named route — don't invent `updateStatus` inside a resource controller.
- Return `to_route(...)`, `back()->with(...)`, `view(...)`, or a response object. Never `echo`, never `dd()`.
- Inject dependencies through the constructor or the method signature; don't call `app()` / `resolve()` in the body.
- Controller middleware in 11+:
  ```php
  class NewsController extends Controller implements HasMiddleware
  {
      public static function middleware(): array
      {
          return ['auth', new Middleware('permission:news.edit', only: ['edit', 'update'])];
      }
  }
  ```

## Middleware

- Registered and aliased in `bootstrap/app.php` under `->withMiddleware()`.
- A middleware answers one yes/no question and either passes the request on or aborts. It does not load page data — that is what a controller or view composer is for.
- `abort(403)` / `abort(404)` over hand-built responses; the exception handler renders them consistently.

## Responses

- **Redirect after every successful POST/PUT/DELETE.** Flash the message with `->with('status', ...)`, read it in the layout.
- Validation errors and `old()` come back automatically on the redirect — never rebuild them by hand.
- JSON endpoints return API Resources (`JsonResource` / `ResourceCollection`), not raw models: a model leaks every column you later add, including the ones you did not mean to publish.
- Set the status code deliberately: `201` on create, `204` on delete, `422` for validation (Laravel does this for you).

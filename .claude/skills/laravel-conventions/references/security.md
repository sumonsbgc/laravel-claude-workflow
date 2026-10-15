# Security checklist (beyond what the guards enforce)

> The PHP and Blade guards already block the classic holes: `env()` outside config, `$request->all()` into a write, interpolated raw SQL, a POST form without `@csrf`, `{!! !!}` on request data, request values as column names, and leftover `dd()`. Per-object authorization is in `auth-and-authorization.md`. This file covers the rest.
>
> Topic list adapted from the community `laravel-security` skill (affaan-m/ECC). Its code examples predate Laravel 11 (`Http/Kernel.php`, `VerifyCsrfToken $except`), so the rules here are rewritten against the 13.x docs: [Rate Limiting](https://laravel.com/docs/13.x/rate-limiting), [Validation](https://laravel.com/docs/13.x/validation), [File Storage](https://laravel.com/docs/13.x/filesystem), and the [13.x upgrade guide](https://laravel.com/docs/13.x/upgrade). *(practice)* marks general guidance that isn't a doc quote.

## Abuse and brute force

- Throttle every auth, password-reset, OTP, contact and upload endpoint. Define named limiters with `RateLimiter::for()` in `AppServiceProvider::boot()`, and attach them with `->middleware('throttle:uploads')`.
- In code paths, `RateLimiter::attempt($key, $max, $callback, $decay)`. Under concurrency, check the value returned by `RateLimiter::increment($key) > $max` (atomic on redis, memcached and database).
- Key limiters by user id **and** IP for authenticated routes, and by IP plus email for login *(practice)*.

## Credentials and sessions

- Passwords: `Password::defaults()` in a provider (e.g. `Password::min(8)->mixedCase()->uncompromised()` in production), and `'password' => ['required', 'confirmed', Password::defaults()]`. `uncompromised()` calls the Have I Been Pwned range API; know that before enabling it in an offline environment.
- Hash with the framework (`Hash::make`, or the `hashed` cast). Never compare a password or token with `==`.
- Regenerate the session on login (`$request->session()->regenerate()`); invalidate and regenerate the token on logout *(practice; starter kits do this)*.
- Laravel 13 skeletons default to session `serialization => json`, so don't put objects in the session.

## Data at rest

- Sensitive columns use the `encrypted` cast (or `encrypted:array`), and hide secrets from serialization with `$hidden` *(practice)*.
- Never log request bodies on auth routes, or tokens, or PII *(practice)*.

## URLs and files

- Time-limited links (unsubscribe, downloads, invitations): `URL::temporarySignedRoute()` plus the `signed` middleware *(practice; stable API)*.
- Private files: `temporaryUrl()` after an authorization check. Never a public bucket path. See `files-and-images.md`.
- Never build a filesystem path or `Storage` key from request input. That's path traversal. Look the path up from your own database row.
- Never fetch a user-supplied URL server-side (`Http::get($request->url)`, `Image::fromUrl()`) without a host allow-list. That's server-side request forgery (SSRF): it can reach cloud metadata endpoints and internal services.

## Production configuration

- `APP_DEBUG=false` and `APP_ENV=production` in production. Debug pages leak env values and stack traces *(practice)*.
- Trusted proxies and HTTPS are configured in `bootstrap/app.php` (`->withMiddleware(fn ($m) => $m->trustProxies(at: …))`), not in a Kernel. Don't trust `*` unless you're behind a known load balancer *(practice)*.
- CSRF exceptions (webhooks only) are configured in `bootstrap/app.php` through the CSRF middleware config. In 13, the middleware is `PreventRequestForgery`. Never add an exception to make a form "work".
- Security headers (CSP, `X-Frame-Options`/`frame-ancestors`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`) aren't a Laravel feature. Add a small middleware or set them at the web server *(practice)*. `X-XSS-Protection` is obsolete, so don't add it.
- Laravel 13 `cache.serializable_classes = false` is a security hardening: keep it, and allow-list specific classes rather than turning it off.

## Supply chain

- Run `composer audit` in CI and before releases *(practice; Composer built-in)*, and `npm audit` for the asset build.
- Commit `composer.lock`. Review new dependencies for maintenance and permissions before adding them. The kit never adds a package unasked.

# Uploads, S3, CDN and images

> **Verified** against [File Storage](https://laravel.com/docs/13.x/filesystem), [Image Manipulation](https://laravel.com/docs/13.x/images) and [Validation → Validating Files](https://laravel.com/docs/13.x/validation#validating-files) (13.x, 2026-10-15). Lines marked *(practice)* are standard AWS/CDN engineering, not quotes from the Laravel docs.

The session report names the default disk, whether the S3 adapter is installed, and which image library is in use. **Match the project:** if it already uses `intervention/image-laravel`, Spatie Media Library, or its own upload service, extend that and don't introduce a second image API.

## 1. Validate before anything touches a disk

```php
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\File;

'photo' => ['required', File::image()                     // jpg, jpeg, png, bmp, gif, webp, avif, heic, heif
    ->max('5mb')                                          // kb / mb / gb / tb suffixes
    ->dimensions(Rule::dimensions()->maxWidth(6000)->maxHeight(6000))],
```

- `image` / `File::image()` **rejects SVG by default** (XSS). Only allow it with `File::image(allowSvg: true)` when SVG is a real requirement, and never serve user SVG from your own domain *(practice)*.
- `mimes`/`types` check the file's **content**. `extensions` checks only the user-supplied name, so never use it alone.
- String rules: `max:` and `size:` for files are **kilobytes**.

## 2. Never trust the client's file name

`getClientOriginalName()` and `getClientOriginalExtension()` are "considered unsafe". Store with `store()` / `storePublicly()` (random `hashName()`), or build the name yourself from `$file->hashName()` / `$file->extension()` (extension from the MIME type). Never put request input into a storage path: that's path traversal.

## 3. Public vs private, and where they live

| Kind | Store with | Serve with |
|---|---|---|
| Public media (news images, avatars, ads) | `->storePublicly('news', 's3')` | `Storage::disk('s3')->url($path)`, which uses the disk's `url` (set it to the CDN host) |
| Private documents (invoices, ID scans) | `->store('invoices', 's3')` (private by default) | `Storage::disk('s3')->temporaryUrl($path, now()->plus(minutes: 5))` after an authorization check |

- S3 needs `composer require league/flysystem-aws-s3-v3 "^3.0" --with-all-dependencies`. Credentials come from `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `AWS_BUCKET` in `.env` and **never** appear in code (the kit's guard blocks `env()` outside `config/`).
- Prefer an IAM role or instance profile over long-lived keys in production *(practice)*.
- `temporaryUrl` works on `s3` and `local` (local needs `'serve' => true` on the disk).
- Store the **path** in the database (`news/abc123.webp`), never the full URL. Then moving to a CDN, or changing it, is a config change, not a data migration *(practice)*.

## 4. CDN (CloudFront or any pull CDN)

- Point the disk's URL at the CDN: `'url' => env('AWS_URL')` on the `s3` disk, with `AWS_URL=https://cdn.example.com`. `Storage::url()` then returns CDN URLs everywhere with no code changes. For built assets, Vite's `ASSET_URL` does the same *(practice)*.
- **Immutable names, long cache** *(practice)*: hashed filenames never change content, so send `Cache-Control: public, max-age=31536000, immutable`. Flysystem's S3 adapter takes it as a write option: `Storage::disk('s3')->put($path, $bytes, ['visibility' => 'public', 'CacheControl' => 'public, max-age=31536000, immutable'])`. "Replacing" an image means writing a new path and updating the row. Then you never need CDN invalidation.
- Keep the bucket private and give the CDN read access only, through CloudFront Origin Access Control *(practice)*. Public objects are then reachable only through the CDN.
- Private files stay off the public CDN path. Use `temporaryUrl` (S3 presigned).

## 5. Processing images

Core API (Laravel 13; needs `intervention/image:^4.0` plus the GD or Imagick extension; driver in `config/images.php` / `IMAGE_DRIVER`):

```php
$path = $request->image('photo')
    ->orient()                   // honour EXIF rotation first
    ->scale(width: 1600)         // never upscales
    ->optimize()                 // WebP, quality 70 by default; ->optimize(format: 'avif', quality: 60)
    ->storePublicly(path: 'news', disk: 's3');
```

- **Queue it.** The docs: "Image manipulation can be CPU and memory-intensive. Consider performing large image processing workloads on a queued job." The request stores the original privately, and the job makes the variants.
- **Responsive variants** *(practice)*: generate a fixed set (e.g. 480/960/1600 px WebP) in the job, store each path, and render `<img srcset>` with `width`/`height` attributes (no layout shift) and `loading="lazy"` below the fold.
- `Image::fromUrl($url)` fetches a remote URL **from your server**. Never pass a user-supplied URL to it without an allow-list of hosts: that's server-side request forgery (SSRF).
- Very large pixel counts can exhaust memory *(practice)*: the `dimensions` rule in step 1 is your cap.

## 6. Direct-to-S3 uploads (large files, serverless)

`Storage::temporaryUploadUrl($path, now()->plus(minutes: 5))` returns `['url' => …, 'headers' => …]` for a presigned upload straight from the browser (`s3` and `local` only). Choose `$path` on the server (`'uploads/'.Str::uuid()`), not from the client. After upload, validate the object server-side (size, MIME) in a job before using it *(practice)*: skipping your validation layer must not mean skipping validation.

## 7. Testing

```php
Storage::fake('s3');
$this->actingAs($editor)->post('/news', ['photo' => UploadedFile::fake()->image('p.jpg', 1200, 800)]);
Storage::disk('s3')->assertExists($news->fresh()->photo_path);
```

For the ownership tests (who may replace or delete an image), see `auth-and-authorization.md`.

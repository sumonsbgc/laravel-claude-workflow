# Post / Page content: the Gutenberg block editor

> **Kit rule:** every **Post** or **Page** module (news posts, articles, static pages, any long-form body field) uses the **Gutenberg block editor** for its content. **Never CKEditor, TinyMCE, Summernote, Quill or Trix.** The planner adds this to every such task, and the edit guard warns if one of those editors appears in Post/Page code. This rule is the user's explicit requirement, so the React and `@wordpress/*` dependencies it needs are pre-approved for these modules, and only for them.
>
> **Sources** (checked 2026-10-15): WordPress Block Editor Handbook, ["Building a custom block editor"](https://developer.wordpress.org/block-editor/how-to-guides/platform/custom-block-editor/); npm registry metadata for `@wordpress/block-editor` 18.1.0, `@wordpress/block-library` 11.2.0, `@wordpress/blocks` 16.2.0 and `@wordpress/components` 42.0.0 (all published 2026-10-07; peer `react ^18 || ^19`). The island code in step 3 follows the handbook's component tree, **but it hasn't been built in a real project yet**, so check the import paths against `node_modules` the first time.

## Why the official packages, not Laraberg

`van-ons/laraberg` was the usual "Gutenberg for Laravel" package, but its last release is **v2.0.4 from 2023-01-24**. It expects React 17, jQuery and Moment as global scripts. Building on it means pinning an editor that WordPress itself left behind. Instead, mount WordPress's own `@wordpress/block-editor` packages (the same code that powers Gutenberg) as a small React island built by the project's existing Vite. The content format is identical to WordPress `post_content`, so content stays portable.

## 1. Data model

| Column | Notes |
|---|---|
| `title` | string |
| `slug` | unique, generated from the title, editable |
| `content` | **`longText`**: the serialized block grammar (HTML with `<!-- wp:paragraph -->` comments), exactly what `serialize()` returns |
| `content_html` | `longText`: the **sanitized** render cache (step 4), so pages never run the sanitizer on read |
| `excerpt` | text, nullable (or derive it from the first paragraph block) |
| `status` | `draft` / `published` / `scheduled` (enum-backed cast) |
| `published_at` | timestamp, nullable; indexed together with `status` for the public listing query |
| `author_id` | `foreignId()->constrained()` |
| `featured_image_path` | **path**, never URL (`files-and-images.md`) |
| `seo_title`, `seo_description` | nullable |
| Pages also: `parent_id` (self-referencing, nullable), `template` (whitelisted enum), `sort_order` | |

Per-object authorization (`auth-and-authorization.md`): authors edit their own drafts, editors edit and publish anything, and only a publisher sets `status = published`. Put this in a Policy, not in the controller.

## 2. Install (once per project; this is the setup task for the first Post/Page module)

```bash
npm install react react-dom @wordpress/block-editor @wordpress/block-library @wordpress/blocks @wordpress/components @wordpress/format-library
npm install -D @vitejs/plugin-react
```

Add `react()` to `vite.config.*` plugins and a separate entry, e.g. `resources/js/block-editor.jsx`, loaded **only** on the Post/Page create/edit screens (`@vite('resources/js/block-editor.jsx')`). The public site doesn't ship React; the front end only needs the block CSS.

## 3. The editor island

```jsx
// resources/js/block-editor.jsx — mounted on <div data-block-editor data-input="content">
import { createRoot } from 'react-dom/client'
import { useState } from 'react'
import { BlockEditorProvider, BlockCanvas, BlockInspector } from '@wordpress/block-editor'
import { registerCoreBlocks } from '@wordpress/block-library'
import { parse, serialize } from '@wordpress/blocks'
import '@wordpress/format-library'                         // bold/italic/link toolbar formats
import '@wordpress/components/build-style/style.css'
import '@wordpress/block-editor/build-style/style.css'
import '@wordpress/block-library/build-style/style.css'
import '@wordpress/block-library/build-style/editor.css'

registerCoreBlocks()

function Editor({ input, uploadUrl, csrf }) {
  const [blocks, setBlocks] = useState(() => parse(input.value))
  const sync = (next) => { setBlocks(next); input.value = serialize(next) }   // the form posts the hidden textarea
  const settings = {
    allowedBlockTypes: ALLOWED_BLOCKS,
    mediaUpload: ({ filesList, onFileChange, onError }) => uploadImages(filesList, uploadUrl, csrf, onFileChange, onError),
  }
  return (
    <BlockEditorProvider value={blocks} onInput={sync} onChange={sync} settings={settings}>
      <div className="be-layout"><BlockCanvas height="600px" /><aside><BlockInspector /></aside></div>
    </BlockEditorProvider>
  )
}

document.querySelectorAll('[data-block-editor]').forEach((el) => {
  const input = document.getElementById(el.dataset.input)
  createRoot(el).render(<Editor input={input} uploadUrl={el.dataset.uploadUrl} csrf={el.dataset.csrf} />)
})
```

- **Allow-list the blocks.** Static content blocks only, e.g. `core/paragraph`, `core/heading`, `core/list`, `core/list-item`, `core/quote`, `core/image`, `core/gallery`, `core/table`, `core/separator`, `core/buttons`, `core/button`, `core/columns`, `core/column`, `core/group`, `core/pullquote`. Leave out dynamic blocks that need WordPress's PHP (`core/latest-posts`, `core/navigation`, …), and `core/html` unless you accept raw HTML from authors. Add `core/embed` only together with a server-side oEmbed endpoint.
- **The Blade form stays a normal form:** `@csrf`, a hidden `<textarea id="content" name="content">{{ old('content', $post->content) }}</textarea>`, a FormRequest, a redirect. Without JavaScript the textarea still submits, so the editor is an enhancement, not a requirement.
- **Media uploads** (`mediaUpload`) POST to a Laravel route, e.g. `POST /admin/media`. It takes `auth` plus a policy, a FormRequest with `File::image()->max('5mb')->dimensions(...)`, `->storePublicly('posts', 's3')`, and returns `{ id, url, alt }`, the URL coming from `Storage::url()` (the CDN host). Follow `files-and-images.md`, and queue the variants.
- **Styling:** Tailwind v4 Preflight resets elements the editor relies on. Keep the editor inside its own container and check headings, lists and buttons render inside the canvas.

## 4. Saving and rendering: sanitize once, on save

Block content is HTML written in the browser. Anyone who can post to the form (a compromised editor account, a forged request) can put `<script>` or `onerror=` in it. So:

1. In the service/action that saves the post, validate `content` as a string with a sane max length, and keep the raw block grammar in `content`, so it can be edited again later.
2. Produce `content_html` with an allow-list sanitizer, and store it. Use **`symfony/html-sanitizer`** (a maintained Symfony component). Allow the tags and attributes your allowed blocks emit (`p, h2–h6, ul, ol, li, blockquote, figure, figcaption, img[src|alt|width|height|loading], a[href|rel|target], table…`, `class` for block classes), plus `img src` only from your CDN or storage host. HTML comments can be dropped from the rendered copy.
3. Render with `{!! $post->content_html !!}`. That's the **only** unescaped output allowed, because it's the sanitized column. Never output `{!! $post->content !!}` or anything from the request (the Blade guard blocks request data).
4. Load the block styles on the public page: `@wordpress/block-library/build-style/style.css` (and `theme.css` if you want WordPress's default look), bundled by Vite into the site CSS.

## 5. Tests that must exist (`[test]` criteria the planner adds)

- Saving stores the raw grammar in `content` and a sanitized `content_html`. A `<script>` or `onerror` in the input never reaches `content_html`.
- An author can't edit another author's post (403), and only a publisher can publish.
- The media upload rejects non-images, SVG and oversized files, and stores to the configured disk (`Storage::fake('s3')`).
- The public page renders `content_html` and shows only `published` posts whose `published_at` has passed.

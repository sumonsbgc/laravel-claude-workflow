# Forms

## The shape

```blade
<form method="POST" action="{{ route('admin.news.update', $news) }}" enctype="multipart/form-data">
    @csrf
    @method('PUT')

    <div>
        <label for="title" class="block text-sm font-medium">Title</label>
        <input id="title" name="title" type="text"
               value="{{ old('title', $news->title) }}"
               @class(['w-full rounded border px-3 py-2', 'border-red-500' => $errors->has('title')])
               @error('title') aria-invalid="true" aria-describedby="title-error" @enderror>
        @error('title')
            <p id="title-error" class="mt-1 text-sm text-red-600">{{ $message }}</p>
        @enderror
    </div>

    <button type="submit" class="cursor-pointer rounded bg-blue-600 px-4 py-2 text-white">Save</button>
</form>
```

Non-negotiable pieces:

- **`@csrf`** in every state-changing form. Without it the browser gets a 419 and no clue why.
- **`@method('PUT'|'PATCH'|'DELETE')`** when the route is not POST. HTML forms only speak GET and POST.
- **`old('field', $default)`** on every input, so a validation failure does not wipe what the user typed.
- **`@error('field')`** next to the field, not only a summary at the top.
- **`enctype="multipart/form-data"`** whenever there is a file input — its absence produces an empty `$request->file()` and no error.
- **A `<label for>` for every input.** An input whose only label is a placeholder is unusable with a screen reader and unlabelled once the user types.

## Directives that save you conditionals

```blade
<input type="checkbox" name="is_active" value="1" @checked(old('is_active', $news->is_active))>
<option value="{{ $c->id }}" @selected(old('category_id', $news->category_id) == $c->id)>{{ $c->name }}</option>
<button @disabled($news->isLocked())>Save</button>
<input @required($isNew) @readonly(! $canEdit)>
```

## Checkboxes and arrays

An unchecked checkbox sends **nothing**, so `$request->boolean('is_active')` (or a hidden `<input type="hidden" name="is_active" value="0">` before it) is what makes "unchecked" mean false rather than "unchanged".

Array inputs use `name="tags[]"` and validate as `'tags' => ['array'], 'tags.*' => ['exists:tags,id']`. Display errors for `tags.0` with `@error('tags.*')`.

## Delete "buttons"

A link cannot DELETE, and a GET route that deletes will be fired by a crawler:

```blade
<form method="POST" action="{{ route('admin.news.destroy', $news) }}"
      x-data @submit.prevent="confirm('Delete this item?') && $el.submit()">
    @csrf @method('DELETE')
    <button type="submit" class="cursor-pointer text-red-600">Delete</button>
</form>
```

## Flash messages

Set on the redirect (`->with('status', '...')`), rendered once in the layout:

```blade
@if (session('status'))
    <div role="status" class="rounded bg-green-50 p-3 text-green-800">{{ session('status') }}</div>
@endif
```

Use `role="status"` (or `role="alert"` for errors) so the message is announced, not just seen.

## Accessibility checklist for a form

- Every control has a label associated by `for`/`id`.
- The invalid field is marked `aria-invalid="true"` and points at its message with `aria-describedby`.
- Focus is visible on every control (`focus-visible:` styles, never `outline-none` alone).
- The submit button is a `<button type="submit">`, not a div with a click handler.
- Required fields are marked in the label text, not by colour alone.
- Grouped controls (radios, related checkboxes) sit in a `<fieldset>` with a `<legend>`.

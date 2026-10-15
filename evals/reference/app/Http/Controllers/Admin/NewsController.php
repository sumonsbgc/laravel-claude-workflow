<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\News;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;

class NewsController extends Controller
{
    public function index(Request $request): View
    {
        $q = trim((string) $request->query('q', ''));

        $news = News::query()->where('user_id', $request->user()->id)
            ->when($q !== '', fn ($query) => $query->where('title', 'like', '%'.$q.'%'))
            ->latest('id')
            ->get();

        return view('admin.news.index', ['news' => $news, 'q' => $q]);
    }

    public function destroy(News $news): RedirectResponse
    {
        Gate::authorize('delete', $news);
        $news->delete();

        return redirect('/admin/news');
    }
}

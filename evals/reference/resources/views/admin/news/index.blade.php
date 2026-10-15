@extends('layouts.app')

@section('content')
    <h1>{{ \App\Support\NewsLabel::count($news->count()) }}</h1>

    <form method="get" action="{{ route('admin.news.index') }}" role="search">
        <label for="q">Search news</label>
        <input id="q" name="q" value="{{ $q }}">
        <button type="submit">Search</button>
    </form>

    @if ($q !== '' && $news->isEmpty())
        <p>No news match</p>
    @endif

    <ul>
        @foreach ($news as $item)
            <li>
                {{ $item->title }}
                <form method="post" action="{{ route('admin.news.destroy', $item) }}">
                    @csrf
                    @method('DELETE')
                    <button type="submit">Delete</button>
                </form>
            </li>
        @endforeach
    </ul>
@endsection

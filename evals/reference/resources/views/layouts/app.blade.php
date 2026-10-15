<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>@yield('title', 'Eval fixture')</title></head>
<body>
    <main>@yield('content')</main>
    <footer>
        <p>Newsroom</p>
        <a href="{{ route('home') }}">Home</a>
    </footer>
</body>
</html>

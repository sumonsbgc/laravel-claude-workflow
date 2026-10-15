<?php

use App\Http\Controllers\Admin\NewsController;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;

Route::view('/', 'home')->name('home');

Route::middleware('auth')->prefix('admin')->name('admin.')->group(function () {
    Route::get('/news', [NewsController::class, 'index'])->name('news.index');
    Route::delete('/news/{news}', [NewsController::class, 'destroy'])->name('news.destroy');
});

// Eval harness only: sign in as a seeded user. Never registered outside the local environment.
if (app()->environment('local')) {
    Route::get('/__eval/login/{id}', function (int $id) {
        Auth::loginUsingId($id);

        return redirect('/');
    });
}

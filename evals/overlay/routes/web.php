<?php

use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;

Route::view('/', 'home')->name('home');

// Eval harness only: sign in as a seeded user. Never registered outside the local environment.
if (app()->environment('local')) {
    Route::get('/__eval/login/{id}', function (int $id) {
        Auth::loginUsingId($id);

        return redirect('/');
    });
}

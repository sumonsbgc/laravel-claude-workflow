<?php

// Hidden from the agent. Authorization by behaviour, with a positive control so a broken
// route can't pass as a correct refusal.
use App\Models\News;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

beforeEach(fn () => $this->seed());

test('deleting another user\'s news is forbidden and changes nothing', function () {
    $this->actingAs(User::find(1))->delete('/admin/news/3')->assertForbidden();
    expect(News::find(3))->not->toBeNull();
});

test('deleting your own news works and redirects to the list (positive control)', function () {
    $this->actingAs(User::find(1))->delete('/admin/news/2')->assertRedirect('/admin/news');
    expect(News::find(2))->toBeNull();
});

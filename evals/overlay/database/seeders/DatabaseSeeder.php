<?php

namespace Database\Seeders;

use App\Models\News;
use App\Models\User;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $u1 = User::factory()->create(['id' => 1, 'name' => 'U1', 'email' => 'u1@example.test']);
        $u2 = User::factory()->create(['id' => 2, 'name' => 'U2', 'email' => 'u2@example.test']);

        foreach ([[1, $u1, 'Website redesign'], [2, $u1, 'Mobile app'], [3, $u2, 'Someone else’s story']] as [$id, $user, $title]) {
            $n = new News(['title' => $title, 'body' => "Body of {$title}"]);
            $n->id = $id;
            $n->user()->associate($user)->save();
        }
    }
}

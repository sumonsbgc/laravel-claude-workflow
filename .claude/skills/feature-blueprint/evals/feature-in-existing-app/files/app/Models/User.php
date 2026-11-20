<?php

declare(strict_types=1);

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;

class User extends Authenticatable
{
    protected $fillable = ['name', 'email', 'password'];

    protected function casts(): array
    {
        return ['is_admin' => 'boolean', 'password' => 'hashed'];
    }
}

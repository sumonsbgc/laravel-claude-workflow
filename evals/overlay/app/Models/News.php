<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class News extends Model
{
    protected $fillable = ['title', 'body'];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}

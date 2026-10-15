<?php

namespace App\Support;

final class NewsLabel
{
    public static function count(int $n): string
    {
        return match (true) {
            $n === 0 => 'No news',
            $n === 1 => '1 news item',
            default => "{$n} news items",
        };
    }
}

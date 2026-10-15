<?php

use App\Support\NewsLabel;

test('labels zero, one and many', function () {
    expect(NewsLabel::count(0))->toBe('No news')
        ->and(NewsLabel::count(1))->toBe('1 news item')
        ->and(NewsLabel::count(3))->toBe('3 news items');
});

<?php

// Hidden from the agent: copied in only after the run, so it can't be tuned against.
use App\Support\NewsLabel;

test('zero', fn () => expect(NewsLabel::count(0))->toBe('No news'));
test('one', fn () => expect(NewsLabel::count(1))->toBe('1 news item'));
test('many', fn () => expect(NewsLabel::count(3))->toBe('3 news items'));
test('large', fn () => expect(NewsLabel::count(12))->toBe('12 news items'));

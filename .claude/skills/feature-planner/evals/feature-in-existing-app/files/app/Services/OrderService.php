<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\Order;
use Illuminate\Support\Facades\DB;

class OrderService
{
    public function place(int $userId, int $subtotalCents, string $currency): Order
    {
        return DB::transaction(fn (): Order => Order::create([
            'user_id' => $userId,
            'subtotal_cents' => $subtotalCents,
            'currency' => $currency,
        ]));
    }
}

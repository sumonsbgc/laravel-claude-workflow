<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\Order;
use App\Services\OrderService;
use Illuminate\Contracts\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class OrderController extends Controller
{
    public function __construct(private readonly OrderService $orders) {}

    public function store(Request $request): RedirectResponse
    {
        $order = $this->orders->place(
            $request->user()->id,
            $request->integer('subtotal_cents'),
            'USD',
        );

        return to_route('orders.show', $order);
    }

    public function show(Order $order): View
    {
        Gate::authorize('view', $order);

        return view('orders.show', ['order' => $order]);
    }
}

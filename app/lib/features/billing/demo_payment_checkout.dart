import 'package:flutter/material.dart';

import '../../api/models/billing_models.dart';
import '../../ui/components.dart';
import 'razorpay_checkout.dart';

/// Mock gateway providers returned by backend-v2 in non-production.
const kDemoPaymentProviders = {'razorpay-mock', 'mock-razorpay'};

bool isDemoPaymentProvider(String? provider) {
  final p = provider?.trim().toLowerCase() ?? '';
  return kDemoPaymentProviders.contains(p);
}

/// UI outcome from the demo/mock payment sheet.
///
/// Settlement is never performed here — callers must call the backend
/// `demo-complete` endpoint. The mock HMAC secret must never live in the client.
enum DemoPaymentChoice { success, failed, cancelled }

/// Routes to the in-app demo checkout for mock providers, otherwise Razorpay.
///
/// Demo path returns [RazorpayCheckoutResult] only for cancel/fail UX parity
/// with the live SDK sheet. Successful demo settlement is handled separately
/// via backend `completeDemoPayment` (no client signature).
Future<RazorpayCheckoutResult> openPaymentCheckout({
  required BuildContext context,
  required CreatePaymentOrderResult order,
  required String ownerName,
  required String ownerEmail,
  String? ownerPhone,
}) {
  if (isDemoPaymentProvider(order.order.provider)) {
    // Prefer [openDemoPaymentCheckout] + backend demo-complete from callers.
    // Kept for API compatibility: maps demo choice to cancel/fail only.
    return openDemoPaymentCheckoutAsRazorpayResult(
      context: context,
      order: order,
    );
  }
  return openRazorpayCheckout(
    order: order,
    ownerName: ownerName,
    ownerEmail: ownerEmail,
    ownerPhone: ownerPhone,
  );
}

/// Shows the demo sheet and returns the user's choice (no signing, no network).
Future<DemoPaymentChoice> openDemoPaymentCheckout({
  required BuildContext context,
  required CreatePaymentOrderResult order,
}) async {
  if (!isDemoPaymentProvider(order.order.provider)) {
    return DemoPaymentChoice.failed;
  }
  final orderId = order.order.orderId.trim();
  if (orderId.isEmpty) {
    return DemoPaymentChoice.failed;
  }

  final choice = await showModalBottomSheet<_DemoPayChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Demo payment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Amount ₹${(order.order.amountPaise / 100).toStringAsFixed(2)} · '
                'Order ${order.order.orderId}',
                style: const TextStyle(color: C.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const InfoNote(
                'This is a mock gateway for development. No real money is charged. '
                'The server settles the payment — the app never holds a payment secret.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, _DemoPayChoice.success),
                child: const Text('Simulate successful payment'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, _DemoPayChoice.failed),
                child: const Text('Simulate failed payment'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, _DemoPayChoice.cancelled),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (choice == null || choice == _DemoPayChoice.cancelled) {
    return DemoPaymentChoice.cancelled;
  }
  if (choice == _DemoPayChoice.failed) {
    return DemoPaymentChoice.failed;
  }
  return DemoPaymentChoice.success;
}

/// Compatibility wrapper used only when callers still expect [RazorpayCheckoutResult].
/// Successful demo payments must not be treated as gateway success here — they
/// require a separate backend `demo-complete` call (see live billing pay flow).
Future<RazorpayCheckoutResult> openDemoPaymentCheckoutAsRazorpayResult({
  required BuildContext context,
  required CreatePaymentOrderResult order,
}) async {
  final choice = await openDemoPaymentCheckout(context: context, order: order);
  switch (choice) {
    case DemoPaymentChoice.cancelled:
      return const RazorpayCheckoutResult.cancelled();
    case DemoPaymentChoice.failed:
      return const RazorpayCheckoutResult.failed(
        'Demo payment failed (simulated).',
      );
    case DemoPaymentChoice.success:
      // Intentionally not a gateway success — no paymentId/signature.
      // Callers that still go through verify-payment will reject this.
      return const RazorpayCheckoutResult.failed(
        'Demo payment requires server-side demo-complete settlement.',
      );
  }
}

enum _DemoPayChoice { success, failed, cancelled }

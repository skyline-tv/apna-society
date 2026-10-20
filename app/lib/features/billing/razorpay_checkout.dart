import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../api/models/billing_models.dart';

/// Result of a Razorpay checkout attempt. Settlement is never implied here.
class RazorpayCheckoutResult {
  const RazorpayCheckoutResult.success({
    required this.orderId,
    required this.paymentId,
    required this.signature,
  })  : cancelled = false,
        errorMessage = null;

  const RazorpayCheckoutResult.cancelled()
      : orderId = null,
        paymentId = null,
        signature = null,
        cancelled = true,
        errorMessage = null;

  const RazorpayCheckoutResult.failed(this.errorMessage)
      : orderId = null,
        paymentId = null,
        signature = null,
        cancelled = false;

  final String? orderId;
  final String? paymentId;
  final String? signature;
  final bool cancelled;
  final String? errorMessage;

  bool get isSuccess =>
      !cancelled &&
      orderId != null &&
      orderId!.trim().isNotEmpty &&
      paymentId != null &&
      paymentId!.trim().isNotEmpty &&
      signature != null &&
      signature!.trim().isNotEmpty;
}

/// Opens Razorpay Checkout using the order payload from the backend.
///
/// Does not mark bills paid. Callers must submit [orderId]/[paymentId]/[signature]
/// to `POST /resident/billing/verify-payment` and refresh from the server.
Future<RazorpayCheckoutResult> openRazorpayCheckout({
  required CreatePaymentOrderResult order,
  required String ownerName,
  required String ownerEmail,
  String? ownerPhone,
}) async {
  final keyId = order.order.keyId?.trim();
  if (keyId == null || keyId.isEmpty) {
    return const RazorpayCheckoutResult.failed(
      'Payment provider key is missing from the server order response.',
    );
  }
  if (order.order.provider != 'razorpay' && order.order.provider != 'mock-razorpay') {
    return RazorpayCheckoutResult.failed(
      'Unsupported payment provider: ${order.order.provider}',
    );
  }

  final razorpay = Razorpay();
  final completer = Completer<RazorpayCheckoutResult>();

  void finish(RazorpayCheckoutResult result) {
    if (!completer.isCompleted) completer.complete(result);
  }

  razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
    finish(RazorpayCheckoutResult.success(
      orderId: response.orderId ?? order.order.orderId,
      paymentId: response.paymentId ?? '',
      signature: response.signature ?? '',
    ));
  });
  razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
    final code = response.code;
    // Razorpay uses code 2 for user cancellation on many platforms.
    if (code == 2) {
      finish(const RazorpayCheckoutResult.cancelled());
      return;
    }
    finish(RazorpayCheckoutResult.failed(
      response.message ?? 'Payment failed (code $code)',
    ));
  });
  razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {
    // External wallet selection is not a settlement signal.
  });

  try {
    razorpay.open({
      'key': keyId,
      'amount': order.order.amountPaise,
      'currency': order.order.currency,
      'name': 'ApnaSociety',
      'description': 'Maintenance bill payment',
      'order_id': order.order.orderId,
      'prefill': {
        'name': ownerName,
        'email': ownerEmail,
        if (ownerPhone != null && ownerPhone.trim().isNotEmpty)
          'contact': ownerPhone.trim(),
      },
      'theme': {'color': '#1E4DB7'},
    });
  } catch (e) {
    razorpay.clear();
    return RazorpayCheckoutResult.failed('$e');
  }

  final result = await completer.future.timeout(
    const Duration(minutes: 15),
    onTimeout: () => const RazorpayCheckoutResult.failed(
      'Payment timed out. If money was deducted, wait for settlement and refresh.',
    ),
  );
  razorpay.clear();
  return result;
}

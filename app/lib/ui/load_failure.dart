import 'dart:io';

import 'package:flutter/material.dart';

import '../api/http/api_exception.dart';
import 'components.dart';

/// Classification of a load/submit failure used to pick icon and copy.
enum FailureKind { offline, unauthorized, forbidden, notFound, server, generic }

const _kNetworkCodes = {
  'NETWORK_TIMEOUT',
  'NETWORK_UNAVAILABLE',
  'NETWORK_ERROR',
  'TLS_ERROR',
};

FailureKind classifyFailure(Object error) {
  if (error is SocketException) return FailureKind.offline;
  if (error is ApiException) {
    if (_kNetworkCodes.contains(error.code)) return FailureKind.offline;
    if (error.isUnauthorized) return FailureKind.unauthorized;
    final code = error.statusCode;
    if (code == null) return FailureKind.generic;
    if (code == 401) return FailureKind.unauthorized;
    if (code == 403) return FailureKind.forbidden;
    if (code == 404) return FailureKind.notFound;
    if (code >= 500) return FailureKind.server;
    return FailureKind.generic;
  }
  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection timed out') ||
      text.contains('no internet')) {
    return FailureKind.offline;
  }
  return FailureKind.generic;
}

/// Standard failure state with retry. Works inside lists, tabs and bodies.
class LoadFailure extends StatelessWidget {
  const LoadFailure({
    super.key,
    required this.error,
    required this.onRetry,
    this.title,
    this.compact = false,
  });

  final Object error;
  final VoidCallback onRetry;
  final String? title;
  final bool compact;

  /// Human-readable message for any thrown error.
  static String messageOf(Object error) {
    if (error is ApiException) {
      final m = error.message.trim();
      if (m.isNotEmpty) return m;
      return 'Request failed (${error.statusCode ?? 'network'}).';
    }
    if (error is StateError) return error.message;
    if (error is SocketException) {
      return 'No internet connection. Check your network and try again.';
    }
    final text = error.toString();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }

  @override
  Widget build(BuildContext context) {
    final kind = classifyFailure(error);
    final (icon, heading, body) = switch (kind) {
      FailureKind.offline => (
          Icons.wifi_off_rounded,
          'You’re offline',
          'Check your internet connection and try again.',
        ),
      FailureKind.unauthorized => (
          Icons.lock_outline_rounded,
          'Session expired',
          'Please sign in again to continue.',
        ),
      FailureKind.forbidden => (
          Icons.block_rounded,
          'Access restricted',
          'Your account does not have permission to view this.',
        ),
      FailureKind.notFound => (
          Icons.search_off_rounded,
          'Not found',
          'This record is no longer available.',
        ),
      FailureKind.server => (
          Icons.cloud_off_rounded,
          'Server unavailable',
          'The service is having trouble right now. Please try again shortly.',
        ),
      FailureKind.generic => (
          Icons.error_outline_rounded,
          title ?? 'Could not load data',
          messageOf(error),
        ),
    };
    final showDetail =
        kind != FailureKind.generic && messageOf(error) != body;
    return Center(
      child: SingleChildScrollView(
        padding:
            EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 20 : 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: compact ? 48 : 64,
            height: compact ? 48 : 64,
            decoration: BoxDecoration(
                color: kind == FailureKind.generic ||
                        kind == FailureKind.server
                    ? C.errorSoft
                    : C.amberSoft,
                borderRadius: BorderRadius.circular(Rd.xl)),
            child: Icon(icon,
                size: compact ? 22 : 28,
                color: kind == FailureKind.generic ||
                        kind == FailureKind.server
                    ? C.error
                    : C.amber),
          ),
          SizedBox(height: compact ? 10 : 16),
          Text(title ?? heading, textAlign: TextAlign.center, style: T.h3),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: T.secondary.copyWith(height: 1.45)),
          if (showDetail) ...[
            const SizedBox(height: 6),
            Text(messageOf(error),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: T.caption.copyWith(color: C.faint)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ]),
      ),
    );
  }
}

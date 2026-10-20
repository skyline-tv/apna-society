import 'package:flutter/material.dart';

import '../api/http/api_exception.dart';
import 'components.dart';

/// Shared loading / empty / error body used by live API screens.
class LoadFailure extends StatelessWidget {
  const LoadFailure({
    super.key,
    required this.error,
    this.onRetry,
    this.title = 'Could not load data',
  });

  final Object error;
  final VoidCallback? onRetry;
  final String title;

  static String messageOf(Object error) {
    if (error is ApiException) return error.message;
    if (error is StateError) return error.message;
    return '$error';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
              '$title\n${messageOf(error)}',
              icon: Icons.error_outline,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

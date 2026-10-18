import 'package:flutter/material.dart';

/// Shared full-area state views so every screen presents loading, empty,
/// error and permission states consistently.
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : theme.colorScheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String? message;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      StateMessage(icon: icon, title: title, message: message, action: action);
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.title, this.message, this.onRetry});

  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => StateMessage(
    icon: Icons.error_outline,
    title: title,
    message: message,
    isError: true,
    action: onRetry == null
        ? null
        : FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
  );
}

class PermissionDeniedView extends StatelessWidget {
  const PermissionDeniedView({super.key, this.onReselect});

  final VoidCallback? onReselect;

  @override
  Widget build(BuildContext context) => StateMessage(
    icon: Icons.folder_off_outlined,
    title: 'Vault access was lost',
    message:
        'Android no longer allows Sapphire to read this folder. This can '
        'happen if the folder was moved, deleted, or access was revoked. '
        'Your notes are not deleted — choose the folder again to continue.',
    isError: true,
    action: onReselect == null
        ? null
        : FilledButton.icon(
            onPressed: onReselect,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose folder again'),
          ),
  );
}

/// A clearly labelled banner for functionality that is not implemented yet.
class NotYetAvailable extends StatelessWidget {
  const NotYetAvailable({super.key, required this.feature, this.phase});

  final String feature;
  final String? phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: ListTile(
        leading: Icon(Icons.construction, color: scheme.tertiary),
        title: Text('$feature is not available yet'),
        subtitle: phase == null ? null : Text('Planned for $phase.'),
      ),
    );
  }
}

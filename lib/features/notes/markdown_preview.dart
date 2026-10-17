import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Rendered Markdown. Remote images are never fetched (privacy: opening a
/// note must not contact third-party servers); a placeholder is shown.
class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({super.key, required this.text, this.onTapLink});

  final String text;
  final void Function(String text, String? href)? onTapLink;

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: text,
      selectable: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      onTapLink: (t, href, _) => onTapLink?.call(t, href),
      imageBuilder: (uri, title, alt) => Chip(
        avatar: const Icon(Icons.image_not_supported_outlined, size: 18),
        label: Text(alt?.isNotEmpty == true ? alt! : 'Image not shown'),
      ),
    );
  }
}

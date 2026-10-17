import 'package:flutter/material.dart';

import 'proposals.dart';
import 'text_diff.dart';

/// Preview of an AI-proposed change with explicit Approve / Reject buttons.
class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.proposal,
    required this.onApprove,
    required this.onReject,
  });

  final NoteProposal proposal;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = proposal;
    final lines = p.kind == ProposalKind.update
        ? diffLines(p.oldText ?? '', p.newText)
        : [for (final l in p.newText.split('\n')) DiffLine(DiffOp.added, l)];
    final added = lines.where((l) => l.op == DiffOp.added).length;
    final removed = lines.where((l) => l.op == DiffOp.removed).length;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  p.kind == ProposalKind.create
                      ? Icons.note_add_outlined
                      : Icons.edit_note,
                  color: scheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.kind == ProposalKind.create
                        ? 'Proposed new note: ${p.path}'
                        : 'Proposed edit: ${p.path}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (p.summary != null && p.summary!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(p.summary!),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '+$added  −$removed lines',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final l in _condense(lines))
                      Text(
                        switch (l.op) {
                          DiffOp.added => '+ ${l.text}',
                          DiffOp.removed => '− ${l.text}',
                          DiffOp.same => '  ${l.text}',
                        },
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: switch (l.op) {
                            DiffOp.added => scheme.primary,
                            DiffOp.removed => scheme.error,
                            DiffOp.same => scheme.onSurfaceVariant,
                          },
                          decoration: l.op == DiffOp.removed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            switch (p.status) {
              ProposalStatus.pending => Wrap(
                spacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    onPressed: onApprove,
                    child: Text(
                      p.kind == ProposalKind.create
                          ? 'Approve & create'
                          : 'Approve & save',
                    ),
                  ),
                ],
              ),
              ProposalStatus.applied => _status(
                context,
                Icons.check_circle,
                'Applied',
                scheme.primary,
              ),
              ProposalStatus.rejected => _status(
                context,
                Icons.block,
                'Rejected — nothing changed',
                scheme.onSurfaceVariant,
              ),
              ProposalStatus.failed => _status(
                context,
                Icons.error_outline,
                'Not applied: ${p.error ?? 'error'}',
                scheme.error,
              ),
            },
          ],
        ),
      ),
    );
  }

  Widget _status(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
  ) => Row(
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text, style: TextStyle(color: color)),
      ),
    ],
  );

  /// Collapses long unchanged stretches to keep the preview readable.
  static List<DiffLine> _condense(List<DiffLine> lines) {
    final out = <DiffLine>[];
    var i = 0;
    while (i < lines.length) {
      if (lines[i].op != DiffOp.same) {
        out.add(lines[i++]);
        continue;
      }
      var j = i;
      while (j < lines.length && lines[j].op == DiffOp.same) {
        j++;
      }
      final run = j - i;
      if (run > 6) {
        out.addAll(lines.sublist(i, i + 2));
        out.add(DiffLine(DiffOp.same, '… ${run - 4} unchanged lines …'));
        out.addAll(lines.sublist(j - 2, j));
      } else {
        out.addAll(lines.sublist(i, j));
      }
      i = j;
    }
    return out;
  }
}

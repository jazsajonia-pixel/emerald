import 'package:flutter/material.dart';

import 'note_editor_screen.dart';

Future<void> openNote(BuildContext context, String path) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(path: path)));

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vault/vault_path.dart';
import '../../data/saf_vault_storage.dart';
import '../../data/vault_storage.dart';
import '../notes/note_history.dart';
import '../notes/note_repository.dart';

sealed class VaultState {
  const VaultState();
}

class VaultLoading extends VaultState {
  const VaultLoading();
}

class VaultNone extends VaultState {
  const VaultNone();
}

class VaultAccessLost extends VaultState {
  const VaultAccessLost();
}

class VaultFailure extends VaultState {
  const VaultFailure(this.message);
  final String message;
}

class VaultReady extends VaultState {
  const VaultReady(this.vault, this.entries, {this.scanning = false});
  final VaultHandle vault;
  final List<VaultEntry> entries;
  final bool scanning;

  Iterable<VaultEntry> get notes => entries.where((e) => !e.isDirectory);

  /// Direct children of [dir]: folders first, then notes, each sorted by
  /// name (case-insensitive).
  List<VaultEntry> childrenOf(String dir) {
    final kids = entries.where((e) => VaultPath.parent(e.path) == dir).toList()
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
    return kids;
  }
}

final vaultStorageProvider = Provider<VaultStorage>((ref) => SafVaultStorage());

final noteHistoryProvider = Provider<NoteHistory>((ref) {
  final storage = ref.watch(vaultStorageProvider);
  if (storage is! SafVaultStorage) return const NoHistory();
  return FileNoteHistory(() async => Directory(await storage.appFilesDir()));
});

final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => NoteRepository(
    ref.watch(vaultStorageProvider),
    ref.watch(noteHistoryProvider),
  ),
);

final vaultControllerProvider = NotifierProvider<VaultController, VaultState>(
  VaultController.new,
);

String describeVaultError(Object e) {
  if (e is VaultException) {
    return switch (e.code) {
      VaultErrorCode.permissionDenied =>
        'Emerald no longer has permission to use this folder.',
      VaultErrorCode.notFound => 'The file or folder no longer exists.',
      VaultErrorCode.alreadyExists => 'A note with that name already exists.',
      VaultErrorCode.conflict => 'The note was changed outside Emerald.',
      VaultErrorCode.tooLarge => 'The file is too large to open (limit 8 MB).',
      VaultErrorCode.invalidPath => 'That name or path is not allowed.',
      VaultErrorCode.readOnly => 'This note is read-only.',
      VaultErrorCode.cancelled => 'Cancelled.',
      VaultErrorCode.io => e.message ?? 'A storage error occurred.',
    };
  }
  if (e is InvalidVaultPath) return 'Invalid name: ${e.reason}.';
  return 'Unexpected error.';
}

class VaultController extends Notifier<VaultState> {
  VaultStorage get _storage => ref.read(vaultStorageProvider);

  @override
  VaultState build() {
    Future.microtask(restore);
    return const VaultLoading();
  }

  Future<void> restore() async {
    state = const VaultLoading();
    try {
      final v = await _storage.restoreVault();
      if (v == null) {
        state = const VaultNone();
        return;
      }
      await _scan(v);
    } on VaultException catch (e) {
      state = e.code == VaultErrorCode.permissionDenied
          ? const VaultAccessLost()
          : VaultFailure(describeVaultError(e));
    }
  }

  Future<void> pick() async {
    final previous = state;
    try {
      final v = await _storage.pickVault();
      if (v == null) {
        state = previous is VaultLoading ? const VaultNone() : previous;
        return;
      }
      state = const VaultLoading();
      await _scan(v);
    } on VaultException catch (e) {
      state = e.code == VaultErrorCode.permissionDenied
          ? const VaultAccessLost()
          : VaultFailure(describeVaultError(e));
    }
  }

  Future<void> rescan() async {
    final s = state;
    if (s is! VaultReady) return restore();
    state = VaultReady(s.vault, s.entries, scanning: true);
    await _scan(s.vault);
  }

  Future<void> _scan(VaultHandle v) async {
    try {
      final entries = await _storage.listTree(v);
      state = VaultReady(v, entries);
    } on VaultException catch (e) {
      state = e.code == VaultErrorCode.permissionDenied
          ? const VaultAccessLost()
          : VaultFailure(describeVaultError(e));
    }
  }

  /// Forgets the vault in Emerald only. Files are never touched.
  Future<void> forget() async {
    final s = state;
    if (s is VaultReady) await _storage.forgetVault(s.vault);
    state = const VaultNone();
  }

  /// Updates the listing after Emerald wrote [path], without a full rescan.
  void noteWritten(String path, FileStamp stamp) {
    final s = state;
    if (s is! VaultReady) return;
    final entries = [
      for (final e in s.entries)
        if (e.path != path) e,
      VaultEntry(
        path: path,
        isDirectory: false,
        size: stamp.size,
        lastModified: stamp.lastModified,
      ),
    ];
    state = VaultReady(s.vault, entries);
  }

  void folderCreated(String path) {
    final s = state;
    if (s is! VaultReady) return;
    final have = s.entries.map((e) => e.path).toSet();
    final add = <VaultEntry>[];
    var p = path;
    while (p.isNotEmpty) {
      if (!have.contains(p)) add.add(VaultEntry(path: p, isDirectory: true));
      p = VaultPath.parent(p);
    }
    state = VaultReady(s.vault, [...s.entries, ...add]);
  }
}

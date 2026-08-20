import 'dart:io';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import '../session/pilot_export.dart';

class PilotExportTransferRequest {
  const PilotExportTransferRequest({
    required this.file,
    required this.artifact,
    required this.sharePositionOrigin,
  });

  final File file;
  final PilotExportArtifact artifact;
  final Rect sharePositionOrigin;
}

abstract interface class PilotExportTransfer {
  Future<void> share(PilotExportTransferRequest request);
}

class NativePilotExportTransfer implements PilotExportTransfer {
  const NativePilotExportTransfer();

  @override
  Future<void> share(PilotExportTransferRequest request) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(request.file.path, mimeType: 'application/json'),
        ],
        fileNameOverrides: <String>[request.artifact.filename],
        title: request.artifact.filename,
        sharePositionOrigin: request.sharePositionOrigin,
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

class ReportDownloadResult {
  const ReportDownloadResult({
    required this.filename,
    required this.uri,
    required this.location,
  });

  final String filename;
  final String uri;
  final String location;
}

class ReportExportService {
  const ReportExportService({
    MethodChannel channel = const MethodChannel('medicare/report_files'),
  }) : _channel = channel;

  final MethodChannel _channel;

  static String sanitizeFilename(String filename) {
    var stem = filename
        .replaceAll(RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|]'), '_')
        .trim()
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (stem.toLowerCase().endsWith('.pdf')) {
      stem = stem.substring(0, stem.length - 4);
    }
    stem = stem.trim().replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (stem.isEmpty) stem = 'MediCare_Report';

    final bounded = StringBuffer();
    var length = 0;
    for (final rune in stem.runes) {
      final character = String.fromCharCode(rune);
      final bytes = utf8.encode(character).length;
      if (length + bytes > 200) break;
      bounded.write(character);
      length += bytes;
    }
    return '$bounded.pdf';
  }

  Future<ReportDownloadResult?> download({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Saving to Downloads is available on Android. You can still share the PDF.',
      );
    }
    final snapshot = _pdfSnapshot(bytes);

    Object? response;
    try {
      response = await _channel.invokeMethod<Object?>('savePdf', {
        // Download the completed preview document; never build another version.
        'bytes': snapshot,
        'filename': sanitizeFilename(filename),
      });
    } on MissingPluginException {
      throw UnsupportedError(
        'PDF downloads are unavailable on this device. Please use Share.',
      );
    }
    if (response is Map && response['cancelled'] == true) return null;
    if (response is! Map) throw _unconfirmedSave();
    final savedName = response['filename'];
    final uri = response['uri'];
    final location = response['location'];
    final destination = uri is String ? Uri.tryParse(uri) : null;
    if (savedName is! String ||
        savedName.trim().isEmpty ||
        uri is! String ||
        destination == null ||
        destination.scheme != 'content' ||
        destination.host.isEmpty ||
        location is! String ||
        location.trim().isEmpty) {
      throw _unconfirmedSave();
    }
    return ReportDownloadResult(
      filename: savedName,
      uri: uri,
      location: location,
    );
  }

  Future<bool> share({
    required Uint8List bytes,
    required String filename,
  }) async {
    final snapshot = _pdfSnapshot(bytes);
    final name = sanitizeFilename(filename);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Printing.sharePdf(bytes: snapshot, filename: name);
    }
    Object? response;
    try {
      response = await _channel.invokeMethod<Object?>('sharePdf', {
        'bytes': snapshot,
        'filename': name,
      });
    } on MissingPluginException {
      throw UnsupportedError(
        'PDF sharing is unavailable in this app build. Please download the PDF instead.',
      );
    }
    if (response is bool) return response;
    throw StateError(
      'The phone did not confirm that the share menu opened. Please try again.',
    );
  }

  static Uint8List _pdfSnapshot(Uint8List bytes) {
    if (bytes.length < 5 ||
        bytes[0] != 37 ||
        bytes[1] != 80 ||
        bytes[2] != 68 ||
        bytes[3] != 70 ||
        bytes[4] != 45) {
      throw ArgumentError('A valid PDF is required before exporting.');
    }
    return Uint8List.fromList(bytes);
  }

  static StateError _unconfirmedSave() => StateError(
    'The phone did not confirm that the PDF was saved. Please try again.',
  );
}

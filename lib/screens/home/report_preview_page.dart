import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../services/report_export_service.dart';
import '../../theme/app_theme.dart';

typedef ReportShareCallback =
    Future<bool> Function({required Uint8List bytes, required String filename});

class ReportPreviewPage extends StatefulWidget {
  const ReportPreviewPage({
    super.key,
    required this.bytes,
    required this.filename,
    this.exportService,
    this.sharePdf,
  });

  final Uint8List bytes;
  final String filename;
  final ReportExportService? exportService;
  final ReportShareCallback? sharePdf;

  @override
  State<ReportPreviewPage> createState() => _ReportPreviewPageState();
}

class _ReportPreviewPageState extends State<ReportPreviewPage> {
  late final Uint8List _bytes;
  late final String _filename;
  late final ReportExportService _exportService;
  String? _busyAction;
  int _previewRevision = 0;

  @override
  void initState() {
    super.initState();
    // Preview and both exports keep this exact snapshot, even if records change.
    _bytes = Uint8List.fromList(widget.bytes).asUnmodifiableView();
    _filename = ReportExportService.sanitizeFilename(widget.filename);
    _exportService = widget.exportService ?? ReportExportService();
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _download() async {
    if (_busyAction != null) return;
    setState(() => _busyAction = 'download');
    try {
      final saved = await _exportService.download(
        bytes: _bytes,
        filename: _filename,
      );
      if (saved == null) {
        _notice('Download cancelled.');
      } else {
        _notice('Saved ${saved.filename} to ${saved.location}.');
      }
    } catch (error) {
      if (error is UnsupportedError) {
        _notice(
          error.message ?? 'PDF downloads are unavailable. Please use Share.',
        );
      } else if (error is ArgumentError) {
        _notice('The PDF is incomplete. Go back and prepare the report again.');
      } else if (error is PlatformException &&
          error.code == 'permission_denied') {
        _notice(
          'Android denied access to the save location. Please try again or use Share.',
        );
      } else if (error is PlatformException &&
          error.message?.trim().isNotEmpty == true) {
        _notice(error.message!);
      } else {
        _notice(
          'Could not save the PDF. Check available storage and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _share() async {
    if (_busyAction != null) return;
    setState(() => _busyAction = 'share');
    try {
      final share = widget.sharePdf ?? _exportService.share;
      if (!await share(bytes: _bytes, filename: _filename)) {
        throw StateError('Share options could not be opened.');
      }
      // The platform confirms the chooser opened, not delivery to a recipient.
      _notice('Share options opened. Choose an app to continue.');
    } catch (error) {
      _notice(
        error is PlatformException && error.message?.trim().isNotEmpty == true
            ? error.message!
            : 'Could not open sharing. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Widget _progress(String action, IconData icon) => _busyAction == action
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon);

  Widget _exportActions(BuildContext context) {
    final download = FilledButton.icon(
      key: const Key('report-download'),
      onPressed: _busyAction == null ? _download : null,
      icon: _progress('download', Icons.download),
      label: Text(_busyAction == 'download' ? 'Saving...' : 'Download'),
    );
    final share = OutlinedButton.icon(
      key: const Key('report-share'),
      onPressed: _busyAction == null ? _share : null,
      icon: _progress('share', Icons.share),
      label: Text(_busyAction == 'share' ? 'Opening...' : 'Share'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 260 ||
            MediaQuery.textScalerOf(context).scale(16) > 20) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [download, const SizedBox(height: 8), share],
          );
        }
        return Row(
          children: [
            Expanded(child: download),
            const SizedBox(width: 12),
            Expanded(child: share),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.paleBlue,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: AppTheme.navy,
      title: const Text('PDF Preview'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            _filename,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: PdfPreview(
            key: ValueKey('report-preview-$_previewRevision'),
            build: (_) async => _bytes,
            pdfFileName: _filename,
            initialPageFormat: PdfPageFormat.a4,
            pageFormats: const {'A4': PdfPageFormat.a4},
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: false,
            allowSharing: false,
            useActions: false,
            dynamicLayout: false,
            enableScrollToPage: true,
            maxPageWidth: 700,
            loadingWidget: const Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Loading PDF preview...'),
                  ],
                ),
              ),
            ),
            onError: (_, _) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Unable to display the preview. You can still download or share this report.',
                      textAlign: TextAlign.center,
                    ),
                    TextButton.icon(
                      key: const Key('report-preview-retry'),
                      onPressed: () => setState(() => _previewRevision++),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry preview'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    bottomNavigationBar: Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _exportActions(context),
        ),
      ),
    ),
  );
}

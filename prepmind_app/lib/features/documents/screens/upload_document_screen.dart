import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/documents_provider.dart';

class UploadDocumentScreen extends ConsumerStatefulWidget {
  final String subjectId;
  const UploadDocumentScreen({super.key, required this.subjectId});

  @override
  ConsumerState<UploadDocumentScreen> createState() =>
      _UploadDocumentScreenState();
}

class _UploadDocumentScreenState extends ConsumerState<UploadDocumentScreen> {
  bool _isUploading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'pptx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      _showStatus('Could not read file. Try again.', success: false);
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'Uploading ${file.name}…';
      _isSuccess = false;
    });

    try {
      final doc = await ref
          .read(documentRepositoryProvider)
          .uploadDocument(widget.subjectId, file);

      setState(() {
        _statusMessage = 'Uploaded! Processing in background…';
      });

      // Invalidate so list refreshes
      ref.invalidate(documentsProvider(widget.subjectId));

      // Poll until ready or failed
      final finished = await ref
          .read(documentRepositoryProvider)
          .pollDocumentStatus(widget.subjectId, doc.id);

      ref.invalidate(documentsProvider(widget.subjectId));

      if (finished.status == 'ready') {
        _showStatus('${file.name} is ready!', success: true);
      } else {
        _showStatus(
          'Processing failed: ${finished.errorMessage ?? 'Unknown error'}',
          success: false,
        );
      }
    } on Exception catch (e) {
      _showStatus('Upload failed: $e', success: false);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showStatus(String message, {required bool success}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _isSuccess = success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider(widget.subjectId));

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Upload button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: _UploadCard(
              isUploading: _isUploading,
              statusMessage: _statusMessage,
              isSuccess: _isSuccess,
              onTap: _isUploading ? null : _pickAndUpload,
            ),
          ),
          const SizedBox(height: 16),
          // Document list
          Expanded(
            child: docsAsync.when(
              data: (docs) {
                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upload_file_outlined,
                            size: 64, color: AppColors.textSecondary),
                        SizedBox(height: 12),
                        Text(
                          'No documents yet.\nUpload PDF, DOCX, or PPTX files.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _DocumentTile(
                    doc: docs[i],
                    onDelete: () async {
                      await ref
                          .read(documentRepositoryProvider)
                          .deleteDocument(docs[i].id);
                      ref.invalidate(documentsProvider(widget.subjectId));
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error loading documents: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  final bool isUploading;
  final String? statusMessage;
  final bool isSuccess;
  final VoidCallback? onTap;

  const _UploadCard({
    required this.isUploading,
    required this.statusMessage,
    required this.isSuccess,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            if (isUploading)
              const SizedBox(
                height: 32,
                width: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              const Icon(Icons.upload_file_outlined,
                  size: 40, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              isUploading ? 'Processing…' : 'Tap to upload document',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              statusMessage ?? 'PDF, DOCX, PPTX • Max 20MB',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: statusMessage != null
                    ? (isSuccess ? Colors.green : AppColors.error)
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final dynamic doc;
  final VoidCallback onDelete;

  const _DocumentTile({required this.doc, required this.onDelete});

  IconData get _fileIcon {
    switch (doc.fileType) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'docx':
        return Icons.description_outlined;
      case 'pptx':
        return Icons.slideshow_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color get _statusColor {
    switch (doc.status) {
      case 'ready':
        return Colors.green;
      case 'processing':
        return Colors.orange;
      case 'failed':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String get _sizeLabel {
    final kb = doc.fileSizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_fileIcon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        doc.status,
                        style: TextStyle(
                            fontSize: 11,
                            color: _statusColor,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _sizeLabel,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.textSecondary, size: 20),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Delete "${doc.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true) onDelete();
  }
}

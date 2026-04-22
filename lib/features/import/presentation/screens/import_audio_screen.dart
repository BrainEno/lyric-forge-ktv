import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// Import audio screen - file selection and project creation entry point.
/// Desktop-first: uses file_picker for local audio file selection.
class ImportAudioScreen extends StatefulWidget {
  const ImportAudioScreen({super.key});

  @override
  State<ImportAudioScreen> createState() => _ImportAudioScreenState();
}

class _ImportAudioScreenState extends State<ImportAudioScreen> {
  File? _selectedFile;
  bool _isCreating = false;

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      // Handle file picker initialization errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法打开文件选择器: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _createProject() async {
    if (_selectedFile == null) return;

    setState(() {
      _isCreating = true;
    });

    try {
      final repository = ServiceLocatorGlobal.I.projectRepository;
      final fileName = _selectedFile!.path.split(Platform.pathSeparator).last;

      // Remove file extension for project name
      final projectName = fileName.replaceAll(
        RegExp(r'\.(mp3|flac|wav|m4a|ogg|aac)$', caseSensitive: false),
        '',
      );

      final project = await repository.createProject(
        name: projectName,
      );

      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          Routes.projectDetailPath(project.id),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('导入音频'),
        backgroundColor: AppColors.bgBase,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // File selection area
              Expanded(
                child: _selectedFile == null
                    ? _FileSelectionPlaceholder(
                        onTap: _pickAudioFile,
                      )
                    : _SelectedFileCard(
                        file: _selectedFile!,
                        onRemove: () => setState(() => _selectedFile = null),
                      ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Action buttons
              if (_selectedFile != null) ...[
                ElevatedButton.icon(
                  onPressed: _isCreating ? null : _createProject,
                  icon: _isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.pureWhite,
                          ),
                        )
                      : const Icon(Icons.create_new_folder_outlined),
                  label: Text(_isCreating ? '创建中...' : '创建工程'),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              OutlinedButton.icon(
                onPressed: _isCreating ? null : _pickAudioFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(_selectedFile == null ? '选择音频文件' : '重新选择'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileSelectionPlaceholder extends StatelessWidget {
  final VoidCallback onTap;

  const _FileSelectionPlaceholder({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          border: Border.all(
            color: AppColors.borderSubtle,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.audio_file_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '选择音频文件',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '支持 MP3 / FLAC / WAV / M4A 格式',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '浏览文件',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedFileCard extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _SelectedFileCard({
    required this.file,
    required this.onRemove,
  });

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final fileSize = file.existsSync() ? file.lengthSync() : 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(26),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: const Icon(
                  Icons.music_note,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _formatFileSize(fileSize),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close),
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

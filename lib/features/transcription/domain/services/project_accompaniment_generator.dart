import '../../../project/domain/models/automatic_accompaniment.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../models/vocal_separation_models.dart';

/// What one 自动生成伴奏 run did (D-060).
class AccompanimentGeneration {
  final VocalSeparationOutcome outcome;

  /// The project after the run (as saved when the run wrote); null when the
  /// run stopped before reading it.
  final ProjectManifest? project;

  const AccompanimentGeneration(this.outcome, {this.project});

  /// The project now plays a separated accompaniment as 纯伴奏.
  bool get linked => project?.audioAsset?.hasAutomaticAccompaniment == true;

  /// One line for the message after the run.
  String get message {
    if (linked) {
      return outcome.status == VocalSeparationStatus.reused
          ? '伴奏已就绪：打开播放器，在“进入 KTV”里选择纯伴奏。'
          : '伴奏已生成：打开播放器，在“进入 KTV”里选择纯伴奏。';
    }
    if (project?.audioAsset?.hasUserAccompaniment == true) {
      return '工程已经有导入的伴奏，没有替换它。';
    }
    return switch (outcome.status) {
      VocalSeparationStatus.skipped => switch (outcome.skipReason!) {
        VocalSeparationSkipReason.disabled => '没有生成伴奏。',
        VocalSeparationSkipReason.unsupportedPlatform => '当前平台暂不支持自动生成伴奏。',
        VocalSeparationSkipReason.userProvidedVocal =>
          '工程使用你导入的人声轨，不能用它自动生成伴奏；请导入已有伴奏。',
        VocalSeparationSkipReason.tooLong => '歌曲超过 15 分钟，暂不支持自动生成伴奏。',
        VocalSeparationSkipReason.sourceMissing => '找不到原始音频，无法生成伴奏。',
      },
      VocalSeparationStatus.failed => switch (outcome.failure!) {
        VocalSeparationFailure.installFailed => '人声分离组件安装失败，没有生成伴奏。',
        VocalSeparationFailure.conversionFailed => '音频转换失败，没有生成伴奏。',
        VocalSeparationFailure.separatorFailed => '人声分离失败，没有生成伴奏。',
        VocalSeparationFailure.silentStem => '没有分离出明显人声（可能本来就是纯音乐），不需要另外的伴奏。',
        VocalSeparationFailure.invalidOutput => '人声分离结果无效，没有生成伴奏。',
      },
      VocalSeparationStatus.separated ||
      VocalSeparationStatus.reused => '人声分离没有产出伴奏文件，请重试。',
    };
  }
}

/// Makes a KTV accompaniment for a project without recognising its lyrics
/// (D-060): the same separation that runs before recognition, on its own.
///
/// Implemented by the recognition workflow so the two never run at once and
/// share its progress stream and [cancel].
abstract interface class ProjectAccompanimentGenerator {
  /// Whether this device can separate a song at all.
  bool get canGenerateAccompaniment;

  /// Separates the project's song (or reuses an earlier separation) and
  /// links the accompaniment unless the user imported one. Progress arrives
  /// on the workflow's progress stream.
  ///
  /// Throws a `TranscriptionException`: busy, input, environment, or
  /// cancelled after the workflow's `cancel`. A separation that does not
  /// work out is an [AccompanimentGeneration] without [AccompanimentGeneration.linked].
  Future<AccompanimentGeneration> generateAccompaniment(String projectId);
}

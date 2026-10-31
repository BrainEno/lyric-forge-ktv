/// 本地 ASR 托管存储位置的一次快照（[AsrManagedStorageService.inspect] 返回）。
///
/// [isDefault] 由实现按平台路径规范化规则计算后注入；本类型保持为纯数据，
/// 不接触文件系统。
class AsrManagedStorageLocation {
  final String activeRoot;
  final String defaultRoot;
  final int managedBytes;
  final bool oldRootRetained;
  final bool isDefault;

  const AsrManagedStorageLocation({
    required this.activeRoot,
    required this.defaultRoot,
    required this.managedBytes,
    required this.isDefault,
    this.oldRootRetained = false,
  });
}

/// 一次托管存储迁移或已有环境接管的结果（复制优先语义见
/// [AsrManagedStorageService]）。
class AsrManagedStorageMoveResult {
  final String sourceRoot;
  final String targetRoot;
  final int copiedBytes;
  final int copiedFiles;
  final bool moved;
  final bool oldRootRetained;

  /// 目标目录原本就是一个可识别的 LyricForge ASR 环境，本次只切换指针，
  /// 没有复制当前环境，也没有删除旧目录。
  final bool adoptedExisting;

  const AsrManagedStorageMoveResult({
    required this.sourceRoot,
    required this.targetRoot,
    required this.copiedBytes,
    required this.copiedFiles,
    required this.moved,
    this.oldRootRetained = false,
    this.adoptedExisting = false,
  });
}

/// 面向 UI 的本地 ASR 托管存储契约：查询当前位置、迁移到用户选择的
/// 父目录、迁回默认位置，或查找并原地接管以前下载的 ASR 环境。
///
/// 迁移是 copy-first：旧环境在暂存副本文件数/字节数核对一致且新位置指针
/// 持久化成功之前保持不动。“识别已有模型”是 pointer-only 操作：只把
/// 托管根指针切换到可识别的已有 `ASRRuntime`，不复制、不删除、不下载。
/// 平台相关的文件系统与 macOS security-scoped bookmark 细节由 data 层实现
/// 承担。
abstract class AsrManagedStorageService {
  /// 读取当前生效位置、默认位置与托管数据占用。
  Future<AsrManagedStorageLocation> inspect();

  /// 在常见位置有界查找以前下载的 `ASRRuntime` 并原地接管最佳候选。
  ///
  /// 查找范围包括当前/默认位置及其祖先、用户主目录中的常见容器，以及
  /// 各磁盘根目录下有限层级的 `LyricForge/ASRRuntime` 与
  /// `Models/LyricForge/ASRRuntime`。未找到时返回 `null`，不改变当前指针。
  Future<AsrManagedStorageMoveResult?> discoverAndAdoptExisting();

  /// 从用户粘贴或选择的一个宽容路径中识别已有 `ASRRuntime` 并原地接管。
  ///
  /// [selectedPath] 可以是磁盘根、`Models` 一类容器、`LyricForge`、
  /// `ASRRuntime`、其内部的模型子目录或模型文件。若没有识别到已有环境，
  /// 实现应抛出异常且不得把当前环境迁移到该无关目录。
  Future<AsrManagedStorageMoveResult> adoptExistingAt(String selectedPath);

  /// 把托管环境切换到用户选择的位置。
  ///
  /// 选择普通父目录时，目标是其下的 `LyricForge/ASRRuntime`；也可以直接
  /// 选择磁盘、容器目录、`LyricForge` 或已有的 `ASRRuntime`。若目标已经是
  /// 可识别的 ASR 环境，实现应原地接管并让后续 repair/inspect 复用其中
  /// 模型，不得为了切换目录重复复制或删除该环境。
  Future<AsrManagedStorageMoveResult> moveToParent(
    String selectedParent, {
    void Function(int copiedBytes, int totalBytes)? onProgress,
  });

  /// 把托管环境迁回默认位置。
  Future<AsrManagedStorageMoveResult> moveToDefault({
    void Function(int copiedBytes, int totalBytes)? onProgress,
  });
}

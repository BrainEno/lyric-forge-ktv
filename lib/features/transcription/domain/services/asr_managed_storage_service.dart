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
/// 父目录、或迁回默认位置。
///
/// 迁移是 copy-first：旧环境在暂存副本文件数/字节数核对一致且新位置指针
/// 持久化成功之前保持不动。平台相关的文件系统与 macOS security-scoped
/// bookmark 细节由 data 层实现承担。
abstract class AsrManagedStorageService {
  /// 读取当前生效位置、默认位置与托管数据占用。
  Future<AsrManagedStorageLocation> inspect();

  /// 把托管环境切换到用户选择的位置。
  ///
  /// 选择普通父目录时，目标是其下的 `LyricForge/ASRRuntime`；也可以直接
  /// 选择 `LyricForge` 或已有的 `ASRRuntime`。若目标已经是可识别的 ASR
  /// 环境，实现应原地接管并让后续 repair/inspect 复用其中模型，不得为了
  /// 切换目录重复复制或删除该环境。
  Future<AsrManagedStorageMoveResult> moveToParent(
    String selectedParent, {
    void Function(int copiedBytes, int totalBytes)? onProgress,
  });

  /// 把托管环境迁回默认位置。
  Future<AsrManagedStorageMoveResult> moveToDefault({
    void Function(int copiedBytes, int totalBytes)? onProgress,
  });
}

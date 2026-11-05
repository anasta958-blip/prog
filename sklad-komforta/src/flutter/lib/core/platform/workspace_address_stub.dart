/// На нативных платформах адрес браузера отсутствует.
String readWorkspacePath() => '';
void initializeWorkspaceAddress() {}

/// На нативных платформах переключение разделов не меняет адрес.
void writeWorkspacePath(String path) {}

import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/features/company/company_controller.dart';
import 'package:sklad_komforta_app/features/onboarding/organization_onboarding_page.dart';

/// Полный редактор действующей организации после первичной настройки.
///
/// Он использует тот же набор шагов, что и onboarding, поэтому реквизиты,
/// канбаны, каталог, поля, зависимости, роли и справочники не расходятся между
/// первичным созданием и последующим редактированием.
final class CompanyPage extends StatelessWidget {
  const CompanyPage({required this.controller, super.key});

  final CompanyController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final configuration = controller.configuration;
      if (controller.loading && configuration == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (configuration == null) {
        return _CompanyError(
          message: controller.error ?? 'Настройки организации не найдены.',
          onRetry: controller.initialize,
        );
      }

      return OrganizationOnboardingPage(
        controller: controller.authController,
        settingsDraft: configuration,
        settingsBusy: controller.saving,
        settingsError: controller.error,
        onSettingsSave: controller.saveConfiguration,
      );
    },
  );
}

final class _CompanyError extends StatelessWidget {
  const _CompanyError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42, color: Color(0xFFFF809D)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
        ],
      ),
    ),
  );
}

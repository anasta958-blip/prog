import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';

/// Владеет auth controller и запускает восстановление сессии один раз.
final class AuthFlowPage extends StatefulWidget {
  const AuthFlowPage({
    required this.config,
    this.controller,
    this.initializeController = true,
    super.key,
  });
  final AppConfig config;
  final AuthController? controller;
  final bool initializeController;

  @override
  State<AuthFlowPage> createState() => _AuthFlowPageState();
}

class _AuthFlowPageState extends State<AuthFlowPage> {
  late final AuthController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller = widget.controller ?? AuthController(widget.config);
    if (widget.initializeController) controller.initialize();
  }

  @override
  void dispose() {
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _AuthShell(controller: controller),
  );
}

/// Адаптивная графитовая оболочка выбранного визуального направления.
final class _AuthShell extends StatelessWidget {
  const _AuthShell({required this.controller});
  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    final content = _StageContent(controller: controller);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A1018), Color(0xFF101927)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Padding(
                    padding: EdgeInsets.all(wide ? 32 : 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111A27),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0xFF28384E)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x77000000),
                            blurRadius: 50,
                            offset: Offset(0, 24),
                          ),
                        ],
                      ),
                      child: wide
                          ? Row(
                              children: [
                                const Expanded(
                                  flex: 4,
                                  child: _IdentityPanel(),
                                ),
                                Expanded(flex: 6, child: content),
                              ],
                            )
                          : content,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel();

  @override
  Widget build(BuildContext context) => Container(
    height: double.infinity,
    padding: const EdgeInsets.all(44),
    decoration: const BoxDecoration(
      color: Color(0xFF0D151F),
      borderRadius: BorderRadius.horizontal(left: Radius.circular(27)),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BrandMark(),
        Spacer(),
        Text(
          'Единое рабочее пространство',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        SizedBox(height: 14),
        Text(
          'Каталог, предложения, комплектация и документы с изоляцией данных каждой организации.',
          style: TextStyle(color: Color(0xFF8FA4C2), height: 1.55),
        ),
        Spacer(),
        Text(
          'Защищено паролем, TOTP и управляемыми сессиями',
          style: TextStyle(color: Color(0xFF6F86A5), fontSize: 12),
        ),
      ],
    ),
  );
}

final class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF4D8DFF),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.inventory_2_outlined, size: 22),
        ),
      ),
      SizedBox(width: 14),
      Text(
        'Склад Комфорта',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
    ],
  );
}

final class _StageContent extends StatelessWidget {
  const _StageContent({required this.controller});
  final AuthController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: switch (controller.stage) {
        AuthStage.loading => const Center(child: CircularProgressIndicator()),
        AuthStage.login => _LoginForm(controller: controller),
        AuthStage.changePassword => _PasswordForm(controller: controller),
        AuthStage.setupTotp ||
        AuthStage.verifyTotp => _TotpForm(controller: controller),
        AuthStage.recoveryCodes => _RecoveryCodes(controller: controller),
        AuthStage.organization => _OrganizationForm(controller: controller),
        AuthStage.ready => _SessionsView(controller: controller),
      },
    ),
  );
}

abstract base class _FormState<T extends StatefulWidget> extends State<T> {
  Widget card({
    required String title,
    required String subtitle,
    required List<Widget> children,
    String? error,
  }) => Align(
    alignment: Alignment.center,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF8FA4C2), height: 1.45),
          ),
          const SizedBox(height: 28),
          if (error != null) ...[
            _ErrorBanner(error),
            const SizedBox(height: 18),
          ],
          ...children,
        ],
      ),
    ),
  );

  Widget field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    TextInputType? keyboardType,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) => TextField(
    controller: controller,
    focusNode: focusNode,
    obscureText: obscure,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    enableInteractiveSelection: true,
    contextMenuBuilder: (context, editableTextState) =>
        AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: editableTextState.contextMenuButtonItems,
        ),
    decoration: InputDecoration(labelText: label),
  );
}

final class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.controller});
  final AuthController controller;
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

final class _LoginFormState extends _FormState<_LoginForm> {
  final login = TextEditingController();
  final password = TextEditingController();
  final loginFocus = FocusNode();
  final passwordFocus = FocusNode();

  void submit() {
    if (!widget.controller.busy) {
      widget.controller.login(login.text, password.text);
    }
  }

  @override
  void dispose() {
    login.dispose();
    password.dispose();
    loginFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => card(
    title: 'Вход',
    subtitle:
        'Используйте учётную запись, выданную администратором. Публичная регистрация недоступна.',
    error: widget.controller.error,
    children: [
      field(
        login,
        'Логин',
        focusNode: loginFocus,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => passwordFocus.requestFocus(),
      ),
      const SizedBox(height: 16),
      field(
        password,
        'Пароль',
        obscure: true,
        focusNode: passwordFocus,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => submit(),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: widget.controller.busy ? null : submit,
        child: Text(widget.controller.busy ? 'Проверяем…' : 'Войти'),
      ),
    ],
  );
}

final class _PasswordForm extends StatefulWidget {
  const _PasswordForm({required this.controller});
  final AuthController controller;
  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

final class _PasswordFormState extends _FormState<_PasswordForm> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final passwordFocus = FocusNode();
  final confirmationFocus = FocusNode();

  bool get canSubmit =>
      !widget.controller.busy &&
      password.text.isNotEmpty &&
      password.text == confirmation.text;

  void submit() {
    if (canSubmit) widget.controller.changePassword(password.text);
  }

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    passwordFocus.dispose();
    confirmationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => card(
    title: 'Смена пароля',
    subtitle:
        'Одноразовый пароль необходимо заменить перед подключением двухфакторной защиты.',
    error: widget.controller.error,
    children: [
      field(
        password,
        'Новый пароль',
        obscure: true,
        focusNode: passwordFocus,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => confirmationFocus.requestFocus(),
      ),
      const SizedBox(height: 16),
      field(
        confirmation,
        'Повторите пароль',
        obscure: true,
        focusNode: confirmationFocus,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => submit(),
      ),
      const SizedBox(height: 12),
      const Text(
        'Не менее 12 символов: заглавная и строчная буквы, цифра и специальный символ.',
        style: TextStyle(color: Color(0xFF8FA4C2), fontSize: 12),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: canSubmit ? submit : null,
        child: const Text('Продолжить'),
      ),
    ],
  );
}

final class _TotpForm extends StatefulWidget {
  const _TotpForm({required this.controller});
  final AuthController controller;
  @override
  State<_TotpForm> createState() => _TotpFormState();
}

final class _TotpFormState extends _FormState<_TotpForm> {
  final code = TextEditingController();
  final codeFocus = FocusNode();
  bool recoveryMode = false;

  void submit() {
    if (widget.controller.busy) return;
    if (recoveryMode) {
      widget.controller.verifyRecoveryCode(code.text);
    } else {
      widget.controller.verifyTotp(code.text);
    }
  }

  @override
  void dispose() {
    code.dispose();
    codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.controller.stage == AuthStage.setupTotp;
    return card(
      title: 'Двухфакторная защита',
      subtitle: recoveryMode
          ? 'Введите один из резервных кодов. После успешного входа этот код станет недействительным.'
          : setup
          ? 'Отсканируйте QR-код приложением-аутентификатором и введите текущий код.'
          : 'Введите шестизначный код из приложения-аутентификатора.',
      error: widget.controller.error,
      children: [
        if (setup && widget.controller.otpAuthUri != null) ...[
          Center(
            child: ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: widget.controller.otpAuthUri!,
                  size: 180,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            widget.controller.totpSecret ?? '',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
        field(
          code,
          recoveryMode ? 'Резервный код' : 'Код подтверждения',
          keyboardType: recoveryMode
              ? TextInputType.text
              : TextInputType.number,
          focusNode: codeFocus,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.controller.busy ? null : submit,
          child: const Text('Подтвердить'),
        ),
        if (!setup) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: widget.controller.busy
                ? null
                : () => setState(() {
                    recoveryMode = !recoveryMode;
                    code.clear();
                  }),
            child: Text(
              recoveryMode
                  ? 'Использовать код из приложения'
                  : 'Использовать резервный код',
            ),
          ),
        ],
      ],
    );
  }
}

final class _RecoveryCodes extends StatelessWidget {
  const _RecoveryCodes({required this.controller});
  final AuthController controller;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Резервные коды',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'Сохраните коды в надёжном месте. После закрытия этого экрана они больше не показываются.',
            style: TextStyle(color: Color(0xFF8FA4C2)),
          ),
          const SizedBox(height: 24),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0D151F),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                controller.recoveryCodes.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: controller.continueAfterRecoveryCodes,
            child: const Text('Я сохранил коды'),
          ),
        ],
      ),
    ),
  );
}

final class _OrganizationForm extends StatefulWidget {
  const _OrganizationForm({required this.controller});
  final AuthController controller;
  @override
  State<_OrganizationForm> createState() => _OrganizationFormState();
}

final class _OrganizationFormState extends _FormState<_OrganizationForm> {
  final name = TextEditingController();

  void submit() {
    if (!widget.controller.busy) {
      widget.controller.createOrganization(name.text);
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => card(
    title: 'Новая организация',
    subtitle:
        'Создаётся отдельная изолированная область данных. Название можно будет изменить в настройках.',
    error: widget.controller.error,
    children: [
      field(
        name,
        'Название организации',
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => submit(),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: widget.controller.busy ? null : submit,
        child: const Text('Создать организацию'),
      ),
    ],
  );
}

final class _SessionsView extends StatelessWidget {
  const _SessionsView({required this.controller});
  final AuthController controller;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Активные устройства',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: controller.busy ? null : controller.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Здесь отображаются действующие refresh-сессии вашей учётной записи.',
        style: TextStyle(color: Color(0xFF8FA4C2)),
      ),
      const SizedBox(height: 24),
      for (final session in controller.sessions)
        Card(
          child: ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: Text(
              (session['deviceName'] as String?) ?? 'Неизвестное устройство',
            ),
            subtitle: Text(
              (session['ipAddress'] as String?) ?? 'IP не определён',
            ),
            trailing: session['isCurrent'] == true
                ? const Chip(label: Text('Текущее'))
                : IconButton(
                    tooltip: 'Отозвать сессию',
                    onPressed: controller.busy
                        ? null
                        : () =>
                              controller.revokeSession(session['id'] as String),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
      if (controller.sessions.any(
        (session) => session['isCurrent'] != true,
      )) ...[
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: controller.busy ? null : controller.revokeOtherSessions,
          child: const Text('Завершить остальные сессии'),
        ),
      ],
    ],
  );
}

final class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF3A1E27),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF7A3447)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF809D)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

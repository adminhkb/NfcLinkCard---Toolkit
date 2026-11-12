// Écrans d'accès : connexion, code de sécurité, attente et ERP injoignable.
// Même parcours et même présentation que l'ERP.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nlc_toolkit/erp/auth_controller.dart';
import 'package:nlc_toolkit/erp/trusted_device.dart';
import 'package:nlc_toolkit/generated/i18n/app_localizations.dart';
import 'package:nlc_toolkit/gui/design/nlc_theme.dart';
import 'package:nlc_toolkit/gui/design/nlc_widgets.dart';
import 'package:provider/provider.dart';

/// Texte d'un message d'accès. Un refus de code est expliqué par le serveur, en français ;
/// une erreur inattendue garde sa phrase générale, suivie du détail technique.
String authNoticeText(AppLocalizations l, AuthNotice notice, String? detail) {
  if (detail != null && detail.isNotEmpty) {
    if (notice == AuthNotice.invalidCode) return detail;
    if (notice == AuthNotice.unknown) return '${l.nlc_auth_unknown}\n$detail';
  }
  return switch (notice) {
    AuthNotice.invalidCredentials => l.nlc_auth_invalid_credentials,
    AuthNotice.userDisabled => l.nlc_auth_user_disabled,
    AuthNotice.tooManyAttempts => l.nlc_auth_too_many_attempts,
    AuthNotice.sessionExpired => l.nlc_auth_session_expired,
    AuthNotice.notAuthorized => l.nlc_auth_not_authorized,
    AuthNotice.network => l.nlc_auth_network,
    AuthNotice.configuration => l.nlc_auth_configuration,
    AuthNotice.unsupportedSecondFactor => l.nlc_auth_unsupported_second_factor,
    AuthNotice.invalidCode => l.nlc_2fa_invalid_code,
    AuthNotice.unknown => l.nlc_auth_unknown,
  };
}

/// Masque une adresse e-mail comme l'ERP : `a***n@h*****.fr`.
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0 || at == email.length - 1) return email;
  final local = email.substring(0, at);
  final domain = email.substring(at + 1);
  final maskedLocal = local.length > 2
      ? '${local[0]}${'*' * (local.length - 2)}${local[local.length - 1]}'
      : '${local[0]}*';
  final dot = domain.indexOf('.');
  final maskedDomain = domain.length > 3 && dot > 0
      ? '${domain[0]}${'*' * (dot - 1)}${domain.substring(dot)}'
      : domain;
  return '$maskedLocal@$maskedDomain';
}

/// Choisit l'écran selon l'état de l'accès. [builder] construit l'application une fois ouverte.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.configured, required this.builder});

  /// L'application a été compilée avec la configuration de l'ERP.
  final bool configured;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (!configured) return const ConfigMissingPage();
    final stage = context.select<AuthController, AuthStage>(
      (auth) => auth.stage,
    );
    final Widget screen = switch (stage) {
      AuthStage.starting => const AuthSplash(key: ValueKey('splash')),
      AuthStage.verifying => const AuthSplash(
        key: ValueKey('splash'),
        showLabel: true,
      ),
      AuthStage.signedOut => const LoginPage(key: ValueKey('login')),
      AuthStage.secondFactor => const TwoFactorPage(key: ValueKey('code')),
      AuthStage.unreachable => const UnreachablePage(
        key: ValueKey('unreachable'),
      ),
      AuthStage.ready => KeyedSubtree(
        key: const ValueKey('app'),
        child: builder(context),
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: screen,
    );
  }
}

/// Fond des écrans d'accès : le motif, un halo indigo et une carte centrée.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Nlc.canvas,
      body: NlcBackground(
        dim: 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.25),
              radius: 1.1,
              colors: [
                Nlc.indigo500.withValues(alpha: 0.14),
                Colors.transparent,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte sombre des écrans d'accès. [topBar] ajoute le liseré dégradé de l'écran de sécurité.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child, this.topBar = false});

  final Widget child;
  final bool topBar;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Nlc.slate950,
        borderRadius: BorderRadius.circular(
          topBar ? Nlc.radiusDialog : Nlc.radiusCard,
        ),
        border: Border.all(color: Nlc.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 50,
            offset: Offset(0, 25),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topBar)
            Container(
              height: 6,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Nlc.blue500, Nlc.indigo500, Nlc.purple500],
                ),
              ),
            ),
          Padding(padding: const EdgeInsets.all(32), child: child),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Nlc.red500.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Nlc.radius),
        border: Border.all(color: Nlc.red500.withValues(alpha: 0.2)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Nlc.red400, fontSize: 12, height: 1.4),
      ),
    );
  }
}

const _fieldPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 16);

/* ─────────────── Connexion ─────────────── */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final auth = context.read<AuthController>();
    if (auth.busy || _email.text.trim().isEmpty || _password.text.isEmpty) {
      return;
    }
    auth.signIn(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l = AppLocalizations.of(context)!;
    final notice = auth.notice;

    return AuthBackdrop(
      child: AuthCard(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: NlcBrand(size: 26)),
              const SizedBox(height: 8),
              Text(
                l.nlc_login_subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Nlc.slate400, fontSize: 14),
              ),
              const SizedBox(height: 24),
              if (notice != null) ...[
                _ErrorBox(authNoticeText(l, notice, auth.noticeDetail)),
                const SizedBox(height: 16),
              ],
              NlcFieldLabel(l.nlc_login_email),
              TextField(
                controller: _email,
                autofocus: true,
                enabled: !auth.busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                onSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: InputDecoration(
                  hintText: l.nlc_login_email_hint,
                  contentPadding: _fieldPadding,
                ),
              ),
              const SizedBox(height: 16),
              NlcFieldLabel(l.nlc_login_password),
              TextField(
                controller: _password,
                focusNode: _passwordFocus,
                enabled: !auth.busy,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '••••••••',
                  contentPadding: _fieldPadding,
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? l.nlc_login_show_password
                        : l.nlc_login_hide_password,
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: auth.busy ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: auth.busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(l.nlc_login_submit),
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0x991E293B)),
              const SizedBox(height: 14),
              Text(
                l.nlc_login_footer,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Nlc.slate500,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ─────────────── Code de sécurité ─────────────── */

class TwoFactorPage extends StatefulWidget {
  const TwoFactorPage({super.key});

  @override
  State<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<TwoFactorPage> {
  final _code = TextEditingController();
  bool _remember = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    // Comme dans l'ERP, le code part dès l'affichage de l'écran.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthController>();
      if (auth.codeSentAt == null) auth.sendCode();
    });
    // Fait avancer le compte à rebours du renvoi.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          context.read<AuthController>().codeResendWait > Duration.zero) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    if (auth.busy || _code.text.length != 6) return;
    final accepted = await auth.verifyCode(
      _code.text,
      rememberDevice: _remember,
    );
    if (!accepted && mounted) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l = AppLocalizations.of(context)!;
    final notice = auth.notice;
    final trustNotice = auth.trustNotice;
    final wait = auth.codeResendWait;
    final email = auth.user?.email ?? '';
    final ready = _code.text.length == 6 && !auth.busy;

    return AuthBackdrop(
      child: AuthCard(
        topBar: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: NlcIconBox(Icons.lock_outline_rounded, size: 50),
            ),
            const SizedBox(height: 14),
            Text(
              l.nlc_2fa_title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.nlc_2fa_intro,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Nlc.slate400,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              email.isEmpty ? l.nlc_2fa_your_email : maskEmail(email),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Nlc.indigo300,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            if (notice != null) ...[
              NlcNotice(
                tone: NlcTone.danger,
                message: authNoticeText(l, notice, auth.noticeDetail),
              ),
              const SizedBox(height: 16),
            ] else if (trustNotice != null) ...[
              NlcNotice(
                tone: NlcTone.warning,
                icon: Icons.schedule_rounded,
                message: trustNotice == TrustNotice.expired
                    ? l.nlc_2fa_expired_notice(trustedDeviceDays)
                    : l.nlc_2fa_revoked_notice,
              ),
              const SizedBox(height: 16),
            ],
            NlcFieldLabel(l.nlc_2fa_code_label, center: true),
            TextField(
              controller: _code,
              autofocus: true,
              enabled: !auth.busy,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onSubmitted: (_) => _submit(),
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'RobotoMono',
                fontSize: 30,
                letterSpacing: 12,
              ),
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: const TextStyle(
                  color: Nlc.slate700,
                  fontFamily: 'RobotoMono',
                  fontSize: 30,
                  letterSpacing: 12,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                border: _codeBorder(Nlc.slate800),
                enabledBorder: _codeBorder(Nlc.slate800),
                focusedBorder: _codeBorder(Nlc.indigo500, 2),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(Nlc.radius),
              onTap: auth.busy
                  ? null
                  : () => setState(() => _remember = !_remember),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _remember,
                        onChanged: auth.busy
                            ? null
                            : (value) =>
                                  setState(() => _remember = value ?? false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.nlc_2fa_remember(trustedDeviceDays),
                            style: const TextStyle(
                              color: Nlc.slate300,
                              fontSize: 14,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l.nlc_2fa_remember_hint,
                            style: const TextStyle(
                              color: Nlc.slate500,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _GradientButton(
              onPressed: ready ? _submit : null,
              busy: auth.busy,
              label: auth.busy ? l.nlc_2fa_verifying : l.nlc_2fa_submit,
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: auth.sendingCode || wait > Duration.zero
                    ? null
                    : auth.sendCode,
                style: TextButton.styleFrom(
                  foregroundColor: Nlc.slate400,
                  disabledForegroundColor: Nlc.slate600,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(
                  auth.sendingCode
                      ? l.nlc_2fa_sending
                      : wait > Duration.zero
                      ? l.nlc_2fa_resend_in(
                          wait.inSeconds == 0 ? 1 : wait.inSeconds,
                        )
                      : l.nlc_2fa_resend,
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: auth.busy ? null : () => auth.signOut(),
                style: TextButton.styleFrom(
                  foregroundColor: Nlc.indigo400,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(l.nlc_2fa_back),
              ),
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _codeBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Nlc.radiusCard),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// Bouton de validation en dégradé bleu-indigo.
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.onPressed,
    required this.label,
    this.busy = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Nlc.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: enabled || busy ? Nlc.actionGradient : null,
          color: enabled || busy ? null : Nlc.slate800,
        ),
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled || busy ? Colors.white : Nlc.slate500,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ─────────────── Attente, ERP injoignable, configuration absente ─────────────── */

class AuthSplash extends StatelessWidget {
  const AuthSplash({super.key, this.showLabel = false});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Nlc.canvas,
      body: NlcBackground(
        dim: 0.45,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NlcBrand(size: 26),
              const SizedBox(height: 24),
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Nlc.indigo500,
                ),
              ),
              if (showLabel) ...[
                const SizedBox(height: 18),
                Text(
                  l.nlc_auth_checking,
                  style: const TextStyle(color: Nlc.slate400, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class UnreachablePage extends StatelessWidget {
  const UnreachablePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l = AppLocalizations.of(context)!;
    final notice = auth.notice ?? AuthNotice.network;
    return AuthBackdrop(
      child: AuthCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: NlcIconBox(
                Icons.cloud_off_rounded,
                color: Nlc.amber400,
                size: 50,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l.nlc_unreachable_title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              authNoticeText(l, notice, auth.noticeDetail),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Nlc.slate300,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l.nlc_unreachable_text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Nlc.slate500,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            if (auth.user != null) ...[
              const SizedBox(height: 14),
              Text(
                auth.user!.email,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Nlc.indigo300, fontSize: 13),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: auth.retry,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l.nlc_retry),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => auth.signOut(),
                child: Text(l.nlc_sign_out),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConfigMissingPage extends StatelessWidget {
  const ConfigMissingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AuthBackdrop(
      child: AuthCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NlcIconBox(
              Icons.link_off_rounded,
              color: Nlc.amber400,
              size: 50,
            ),
            const SizedBox(height: 14),
            Text(
              l.nlc_config_missing_title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l.nlc_config_missing_text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Nlc.slate400,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

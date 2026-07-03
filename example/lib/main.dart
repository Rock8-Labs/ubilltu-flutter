import 'package:flutter/material.dart';
import 'package:ubilltu/ubilltu.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const UbilltuExampleApp());

/// Where the hosted payment pages return to after checkout. Must be an
/// allow-listed storefront origin (or a relative path) or the API rejects it —
/// on prod the storefront origin is client.ubilltu.com.
const _returnUrl = 'https://client.ubilltu.com/done';

class UbilltuExampleApp extends StatelessWidget {
  const UbilltuExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ubilltu example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C3AED)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _slug = TextEditingController(text: 'your-store-slug');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  UbilltuClient? _client;
  bool _loading = false;
  bool _loggedIn = false;
  bool _register = false; // login screen toggles to a register form
  bool _tos = false;

  List<Plan> _plans = const [];
  List<Subscription> _subs = const [];
  List<PaymentMethod> _methods = const [];
  List<Invoice> _invoices = const [];
  List<Payment> _payments = const [];
  Map<String, dynamic>? _account;
  Map<String, dynamic>? _balance;
  Map<String, dynamic>? _usage;

  @override
  void dispose() {
    _slug.dispose();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _client?.close();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _msg(UbilltuException e) => e is UbilltuApiException
      ? 'API ${e.statusCode}: ${e.message}'
      : e.message;

  // --------------------------------------------------------------- auth ----

  Future<void> _authenticate({required bool register}) async {
    FocusScope.of(context).unfocus();
    if (register && !_tos) {
      _snack('Accept the terms to register');
      return;
    }
    setState(() => _loading = true);
    final client = UbilltuClient(storefrontSlug: _slug.text.trim());
    try {
      if (register) {
        await client.register(
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim().isEmpty ? null : _name.text.trim(),
          tosAccepted: true,
        );
      } else {
        await client.login(_email.text.trim(), _password.text);
      }
      _client = client;
      await _refresh();
      if (mounted) setState(() => _loggedIn = true);
      _snack(register ? 'Account created' : 'Signed in');
    } on UbilltuException catch (e) {
      _snack(_msg(e));
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _logout() {
    _client?.logout();
    setState(() {
      _loggedIn = false;
      _plans = const [];
      _subs = const [];
      _methods = const [];
      _invoices = const [];
      _payments = const [];
      _account = _balance = _usage = null;
    });
  }

  /// Reload every section. Each call is best-effort so one failing endpoint
  /// doesn't blank the whole dashboard.
  Future<void> _refresh() async {
    final c = _client;
    if (c == null) return;
    Future<void> safe(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {/* section stays empty; other sections still load */}
    }

    await Future.wait([
      safe(() async => _plans = (await c.listPlans()).items),
      safe(() async => _subs = (await c.listSubscriptions()).items),
      safe(() async => _methods = (await c.listPaymentMethods()).items),
      safe(() async => _invoices = (await c.listInvoices()).items),
      safe(() async => _payments = (await c.listPayments()).items),
      safe(() async => _account = await c.account()),
      safe(() async => _balance = await c.balance()),
      safe(() async => _usage = await c.usage()),
    ]);
    if (mounted) setState(() {});
  }

  /// Run a mutating action, then refresh + report.
  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      await _refresh();
      _snack('$label ✓');
    } on UbilltuException catch (e) {
      _snack(_msg(e));
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _launch(String? url, {String? emptyMsg}) async {
    if (url == null || url.isEmpty) {
      _snack(emptyMsg ?? 'No redirect URL returned');
      return;
    }
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok) _snack('Could not open $url');
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue')),
          ],
        ),
      ) ??
      false;

  // ------------------------------------------------------------ payments ----

  Future<void> _buy(Plan plan) async {
    if (!await _confirm('Subscribe to ${plan.name}?',
        'Creates a real subscription and opens the hosted payment page.')) {
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await _client!.signup(plan.id, _returnUrl);
      await _refresh();
      await _launch(r['redirect_url'] as String?,
          emptyMsg: 'Subscribed (no payment page returned)');
    } on UbilltuException catch (e) {
      _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCard() async {
    setState(() => _loading = true);
    try {
      final r = await _client!.setupPaymentMethod(_returnUrl);
      await _launch(r['redirect_url'] as String?);
    } on UbilltuException catch (e) {
      _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _payInvoice(Invoice inv) async {
    final amount = inv.amount;
    if (amount == null) {
      _snack('Invoice has no amount');
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await _client!.checkout(amount,
          currency: inv.currency ?? 'ZAR', invoiceId: inv.id);
      await _launch(r['redirect_url'] as String?);
    } on UbilltuException catch (e) {
      _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPdf(Invoice inv) async {
    setState(() => _loading = true);
    try {
      final bytes = await _client!.invoicePdf(inv.id);
      _snack('invoicePdf ✓ — ${bytes.length} bytes');
    } on UbilltuException catch (e) {
      _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------------------------------- subscription mgmt ----

  Future<Plan?> _pickPlan(String title) {
    return showDialog<Plan>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: _plans
            .map((p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, p),
                  child: Text('${p.name}    ${p.currency ?? ''}${p.price ?? ''}'),
                ))
            .toList(),
      ),
    );
  }

  Future<String?> _pickPolicy() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Apply when?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'END_OF_TERM'),
            child: const Text('End of term (no proration)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'IMMEDIATE'),
            child: const Text('Immediately (prorated)'),
          ),
        ],
      ),
    );
  }

  Future<void> _preview(Subscription sub) async {
    final plan = await _pickPlan('Preview change to…');
    if (plan == null || _client == null) return;
    setState(() => _loading = true);
    try {
      final dry = await _client!.previewChange(sub.id, newPlan: plan.id);
      if (!mounted) return;
      final amount = dry['amount'] ?? dry['total'] ?? dry['balance'] ?? dry;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Dry-run preview'),
          content: Text('Change to ${plan.name}\n\nProjected: $amount'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    } on UbilltuException catch (e) {
      _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changePlan(Subscription sub) async {
    final plan = await _pickPlan('Change to…');
    if (plan == null) return;
    final policy = await _pickPolicy();
    if (policy == null) return;
    await _run('Plan changed',
        () => _client!.changePlan(sub.id, plan.id, policy: policy));
  }

  void _openActions(Subscription sub) {
    final client = _client!;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        void act(Future<void> Function() run) {
          Navigator.pop(ctx);
          run();
        }

        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                title: Text(sub.planName ?? sub.id),
                subtitle: Text('State: ${sub.state ?? '—'}'),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Preview change'),
                onTap: () => act(() => _preview(sub)),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Change plan'),
                onTap: () => act(() => _changePlan(sub)),
              ),
              ListTile(
                leading: const Icon(Icons.pause),
                title: const Text('Pause'),
                onTap: () => act(
                    () => _run('Paused', () => client.pauseSubscription(sub.id))),
              ),
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Resume'),
                onTap: () => act(() =>
                    _run('Resumed', () => client.resumeSubscription(sub.id))),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reactivate'),
                onTap: () => act(() => _run(
                    'Reactivated', () => client.reactivateSubscription(sub.id))),
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                iconColor: Colors.red,
                textColor: Colors.red,
                title: const Text('Cancel'),
                onTap: () => act(() =>
                    _run('Cancelled', () => client.cancelSubscription(sub.id))),
              ),
            ],
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------- build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ubilltu SDK example'),
        actions: [
          if (_loggedIn)
            IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loggedIn
              ? _buildDashboard(context)
              : _buildAuth(context),
    );
  }

  Widget _buildAuth(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        Text(_register ? 'Create account' : 'Sign in',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        TextField(
          controller: _slug,
          decoration: const InputDecoration(
              labelText: 'Storefront slug', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        if (_register) ...[
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Name (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
              labelText: 'Email', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: 'Password', border: OutlineInputBorder()),
        ),
        if (_register)
          CheckboxListTile(
            value: _tos,
            onChanged: (v) => setState(() => _tos = v ?? false),
            title: const Text('I accept the terms of service'),
            contentPadding: EdgeInsets.zero,
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _authenticate(register: _register),
          child: Text(_register ? 'Create account' : 'Sign in'),
        ),
        TextButton(
          onPressed: () => setState(() => _register = !_register),
          child: Text(_register
              ? 'Have an account? Sign in'
              : 'New here? Create an account'),
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleLarge),
      );

  Widget _kv(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return const Text('—');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: m.entries
          .take(8)
          .map((e) => Text('${e.key}: ${e.value}',
              style: const TextStyle(fontSize: 13)))
          .toList(),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Account ----
          _sectionTitle('Account'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv(_account),
                  const Divider(),
                  Text('Balance', style: Theme.of(context).textTheme.labelLarge),
                  _kv(_balance),
                  const Divider(),
                  Text('Usage', style: Theme.of(context).textTheme.labelLarge),
                  _kv(_usage),
                ],
              ),
            ),
          ),

          // ---- Plans ----
          _sectionTitle('Plans'),
          if (_plans.isEmpty) const Text('No plans.'),
          ..._plans.map((p) => Card(
                child: ListTile(
                  title: Text(p.name),
                  subtitle: Text(p.billingPeriod ?? ''),
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text('${p.currency ?? ''}${p.price ?? ''}'),
                      FilledButton.tonal(
                        onPressed: () => _buy(p),
                        child: const Text('Buy'),
                      ),
                    ],
                  ),
                ),
              )),

          // ---- Subscriptions ----
          _sectionTitle('My subscriptions'),
          const Text('Tap a subscription to manage it',
              style: TextStyle(color: Colors.grey)),
          if (_subs.isEmpty) const Text('No subscriptions.'),
          ..._subs.map((s) => Card(
                child: ListTile(
                  title: Text(s.planName ?? s.id),
                  subtitle: Text(s.id),
                  trailing: Text(s.state ?? ''),
                  onTap: () => _openActions(s),
                ),
              )),

          // ---- Payment methods ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('Payment methods'),
              TextButton.icon(
                onPressed: _addCard,
                icon: const Icon(Icons.add_card),
                label: const Text('Add card'),
              ),
            ],
          ),
          if (_methods.isEmpty) const Text('No saved cards.'),
          ..._methods.map((m) => Card(
                child: ListTile(
                  leading: const Icon(Icons.credit_card),
                  title: Text(
                      '${m.cardBrand ?? 'Card'} ····${m.cardLast4 ?? '????'}'),
                  subtitle: Text([
                    if (m.expiryMonth != null && m.expiryYear != null)
                      'exp ${m.expiryMonth}/${m.expiryYear}',
                    if (m.isDefault) 'default',
                  ].join('  ·  ')),
                ),
              )),

          // ---- Invoices ----
          _sectionTitle('Invoices'),
          if (_invoices.isEmpty) const Text('No invoices.'),
          ..._invoices.map((inv) => Card(
                child: ListTile(
                  title: Text('${inv.currency ?? ''}${inv.amount ?? ''}'),
                  subtitle: Text('${inv.status ?? ''}  ·  ${inv.id}'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'PDF',
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        onPressed: () => _openPdf(inv),
                      ),
                      IconButton(
                        tooltip: 'Pay',
                        icon: const Icon(Icons.payment),
                        onPressed: () => _payInvoice(inv),
                      ),
                    ],
                  ),
                ),
              )),

          // ---- Payments history ----
          _sectionTitle('Payments'),
          if (_payments.isEmpty) const Text('No payments.'),
          ..._payments.map((p) => Card(
                child: ListTile(
                  dense: true,
                  title: Text('${p.currency ?? ''}${p.amount ?? ''}'),
                  subtitle: Text(p.status ?? ''),
                ),
              )),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

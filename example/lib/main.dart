import 'package:flutter/material.dart';
import 'package:ubilltu/ubilltu.dart';

void main() => runApp(const UbilltuExampleApp());

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
  final _slug = TextEditingController(text: 'democompany-e6226f1b');
  final _email = TextEditingController();
  final _password = TextEditingController();

  UbilltuClient? _client;
  bool _loading = false;
  bool _loggedIn = false;
  List<Plan> _plans = const [];
  List<Subscription> _subs = const [];

  @override
  void dispose() {
    _slug.dispose();
    _email.dispose();
    _password.dispose();
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

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final client = UbilltuClient(storefrontSlug: _slug.text.trim());
    try {
      await client.login(_email.text.trim(), _password.text);
      _client = client;
      await _refresh();
      if (mounted) setState(() => _loggedIn = true);
      _snack('Signed in');
    } on UbilltuException catch (e) {
      _snack(_msg(e));
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final client = _client;
    if (client == null) return;
    final plans = await client.listPlans();
    final subs = await client.listSubscriptions();
    if (!mounted) return;
    setState(() {
      _plans = plans.items;
      _subs = subs.items;
    });
  }

  void _logout() {
    _client?.logout();
    setState(() {
      _loggedIn = false;
      _plans = const [];
      _subs = const [];
    });
  }

  /// Run a write action, then refresh + report.
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

  Future<Plan?> _pickPlan(String title) {
    return showDialog<Plan>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: _plans
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p),
                child: Text('${p.name}    ${p.currency ?? ''}${p.price ?? ''}'),
              ),
            )
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
              child: const Text('OK'),
            ),
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
    await _run(
      'Plan changed',
      () => _client!.changePlan(sub.id, plan.id, policy: policy),
    );
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
                  () => _run('Paused', () => client.pauseSubscription(sub.id)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Resume'),
                onTap: () => act(
                  () =>
                      _run('Resumed', () => client.resumeSubscription(sub.id)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reactivate'),
                onTap: () => act(
                  () => _run(
                    'Reactivated',
                    () => client.reactivateSubscription(sub.id),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                iconColor: Colors.red,
                textColor: Colors.red,
                title: const Text('Cancel'),
                onTap: () => act(
                  () => _run(
                    'Cancelled',
                    () => client.cancelSubscription(sub.id),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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
          : _buildLogin(context),
    );
  }

  Widget _buildLogin(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        Text('Sign in', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        TextField(
          controller: _slug,
          decoration: const InputDecoration(
            labelText: 'Storefront slug',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _login, child: const Text('Sign in')),
      ],
    );
  }

  Widget _buildDashboard(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Plans', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_plans.isEmpty) const Text('No plans.'),
          ..._plans.map(
            (p) => Card(
              child: ListTile(
                title: Text(p.name),
                subtitle: Text(p.billingPeriod ?? ''),
                trailing: Text('${p.currency ?? ''}${p.price ?? ''}'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'My subscriptions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Tap a subscription to manage it',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (_subs.isEmpty) const Text('No subscriptions.'),
          ..._subs.map(
            (s) => Card(
              child: ListTile(
                title: Text(s.planName ?? s.id),
                subtitle: Text(s.id),
                trailing: Text(s.state ?? ''),
                onTap: () => _openActions(s),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

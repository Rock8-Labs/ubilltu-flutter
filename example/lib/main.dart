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
  final _slug = TextEditingController(text: 'your-store-slug');
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

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final client = UbilltuClient(storefrontSlug: _slug.text.trim());
    try {
      await client.login(_email.text.trim(), _password.text);
      final plans = await client.listPlans();
      final subs = await client.listSubscriptions();
      if (!mounted) return;
      setState(() {
        _client = client;
        _loggedIn = true;
        _plans = plans.items;
        _subs = subs.items;
      });
      _snack('Signed in — ${plans.total} plans, ${subs.total} subscriptions');
    } on UbilltuApiException catch (e) {
      _snack('API ${e.statusCode}: ${e.message}');
    } on UbilltuException catch (e) {
      _snack(e.message);
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
    });
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
      onRefresh: _login,
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
          Text('My subscriptions',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_subs.isEmpty) const Text('No subscriptions.'),
          ..._subs.map(
            (s) => Card(
              child: ListTile(
                title: Text(s.planName ?? s.id),
                trailing: Text(s.state ?? ''),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI Civic Guardian - Screens
///
/// All UI screens live in this one file: Splash, Login, Register,
/// Dashboard (bottom-nav shell + Home tab + Profile tab), Report Issue,
/// Map, and Complaint Tracking (list + detail).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'services.dart';

// ============================================================================
// SPLASH SCREEN
// ============================================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final auth = context.read<AuthProvider>();
    await auth.tryAutoLogin();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            auth.status == AuthStatus.authenticated ? const DashboardScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 88, color: Theme.of(context).colorScheme.onPrimary),
            const SizedBox(height: 16),
            Text(
              'AI Civic Guardian',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// LOGIN SCREEN
// ============================================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.login(_emailController.text.trim(), _passwordController.text);
    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DashboardScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(auth.errorMessage ?? 'Login failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.shield_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('Welcome Back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Sign in to report and track civic issues',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter your email';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: auth.isLoading ? null : _submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Sign In'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text("Don't have an account? Register"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// REGISTER SCREEN
// ============================================================================

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created! Please sign in.')));
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(auth.errorMessage ?? 'Registration failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                      labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder()),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: auth.isLoading ? null : _submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DASHBOARD SHELL (bottom navigation)
// ============================================================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  late final List<Widget> _tabs = const [
    HomeTab(),
    ReportScreen(),
    MapScreen(),
    TrackingListScreen(),
    ProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().refreshCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.add_a_photo_outlined), selectedIcon: Icon(Icons.add_a_photo), label: 'Report'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(
              icon: Icon(Icons.track_changes_outlined), selectedIcon: Icon(Icons.track_changes), label: 'Tracking'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'Resolved':
    case 'Closed':
      return Colors.green;
    case 'In Progress':
      return Colors.orange;
    case 'Reopened':
      return Colors.red;
    default:
      return Colors.blueGrey;
  }
}

// ============================================================================
// HOME TAB
// ============================================================================

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    final complaintProvider = context.read<ComplaintProvider>();
    await complaintProvider.loadDashboardStats(auth.token!);
    await complaintProvider.loadComplaints(auth.token!, mineOnly: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final complaintProvider = context.watch<ComplaintProvider>();
    final stats = complaintProvider.dashboardStats;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${auth.currentUser?.name.split(' ').first ?? 'Citizen'}'),
        actions: [IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () {})],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _StatCard(label: 'Total Submitted', value: '${stats?['total_submitted'] ?? '-'}', icon: Icons.description_outlined, color: Colors.blue),
                _StatCard(label: 'Resolved', value: '${stats?['resolved'] ?? '-'}', icon: Icons.check_circle_outline, color: Colors.green),
                _StatCard(label: 'Pending', value: '${stats?['pending'] ?? '-'}', icon: Icons.hourglass_empty, color: Colors.orange),
                _StatCard(label: 'In Progress', value: '${stats?['in_progress'] ?? '-'}', icon: Icons.autorenew, color: Colors.purple),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Civic Points', style: Theme.of(context).textTheme.labelLarge),
                          Text('${stats?['points'] ?? auth.currentUser?.points ?? 0} points',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Recent Complaints', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (complaintProvider.isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (complaintProvider.complaints.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No complaints yet. Tap Report to submit one!')),
              )
            else
              ...complaintProvider.complaints.take(5).map((c) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(child: Text(c.category.substring(0, 1))),
                      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(c.category),
                      trailing: Chip(
                        label: Text(c.status, style: const TextStyle(fontSize: 11)),
                        backgroundColor: statusColor(c.status).withOpacity(0.15),
                        labelStyle: TextStyle(color: statusColor(c.status)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const Spacer(),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PROFILE TAB
// ============================================================================

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              child: Text(
                (user?.name.isNotEmpty ?? false) ? user!.name.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(user?.name ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
          Center(child: Text(user?.email ?? '', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]))),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: const Text('Civic Points'),
                  trailing: Text('${user?.points ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Role'), trailing: Text(user?.role ?? 'citizen')),
                if (user?.phone != null) ...[
                  const Divider(height: 1),
                  ListTile(leading: const Icon(Icons.phone_outlined), title: const Text('Phone'), trailing: Text(user!.phone!)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language_outlined),
                  title: const Text('Language'),
                  subtitle: const Text('English (Tamil, Hindi coming soon)'),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Theme'),
                  subtitle: const Text('Follows system setting'),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(leading: const Icon(Icons.help_outline), title: const Text('Help Center'), onTap: () {}),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// REPORT SCREEN
// ============================================================================

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _contactController = TextEditingController();

  String _category = kIssueCategories.first;
  String _severity = 'Medium';
  bool _isAnonymous = false;
  bool _isFetchingLocation = false;
  double? _latitude;
  double? _longitude;
  String? _address;
  final List<File> _images = [];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _landmarkController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Please enable location services');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permission denied');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied. Enable it in settings.');
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      String? resolvedAddress;
      try {
        final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          resolvedAddress =
              [p.street, p.subLocality, p.locality, p.postalCode].where((s) => s != null && s.isNotEmpty).join(', ');
        }
      } catch (_) {
        // Reverse geocoding is best-effort; GPS coordinates are captured regardless.
      }

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _address = resolvedAddress;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 5 images allowed')));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (picked != null) setState(() => _images.add(File(picked.path)));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please capture your location before submitting')));
      return;
    }

    final auth = context.read<AuthProvider>();
    final complaintProvider = context.read<ComplaintProvider>();

    final result = await complaintProvider.submitComplaint(
      token: auth.token!,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _category,
      severity: _severity,
      latitude: _latitude!,
      longitude: _longitude!,
      address: _address,
      landmark: _landmarkController.text.trim().isEmpty ? null : _landmarkController.text.trim(),
      isAnonymous: _isAnonymous,
      contactNumber: _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
      images: _images,
    );

    if (!mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Complaint submitted successfully! +10 civic points')));
      _resetForm();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(complaintProvider.errorMessage ?? 'Failed to submit complaint')));
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _descriptionController.clear();
    _landmarkController.clear();
    _contactController.clear();
    setState(() {
      _category = kIssueCategories.first;
      _severity = 'Medium';
      _isAnonymous = false;
      _latitude = null;
      _longitude = null;
      _address = null;
      _images.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final complaintProvider = context.watch<ComplaintProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Report an Issue')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Enter a short title' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration:
                  const InputDecoration(labelText: 'Description', border: OutlineInputBorder(), alignLabelWithHint: true),
              validator: (v) => (v == null || v.trim().length < 5) ? 'Describe the issue' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: kIssueCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _severity,
              decoration: const InputDecoration(labelText: 'Severity', border: OutlineInputBorder()),
              items: kSeverityLevels.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _severity = v!),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined, color: _latitude != null ? Colors.green : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _latitude != null
                            ? (_address ?? '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}')
                            : 'Location not captured yet',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _isFetchingLocation ? null : _fetchLocation,
                      child: _isFetchingLocation
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_latitude != null ? 'Update' : 'Capture'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _landmarkController,
              decoration: const InputDecoration(labelText: 'Landmark (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text('Photos (up to 5)', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ..._images.map((file) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(file, width: 90, height: 90, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => setState(() => _images.remove(file)),
                                child: const CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  InkWell(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      builder: (_) => SafeArea(
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.camera_alt_outlined),
                              title: const Text('Take Photo'),
                              onTap: () {
                                Navigator.pop(context);
                                _pickImage(ImageSource.camera);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: const Text('Choose from Gallery'),
                              onTap: () {
                                Navigator.pop(context);
                                _pickImage(ImageSource.gallery);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Report Anonymously'),
              value: _isAnonymous,
              onChanged: (v) => setState(() => _isAnonymous = v),
            ),
            if (!_isAnonymous) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Contact Number (optional)', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: complaintProvider.isLoading ? null : _submit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: complaintProvider.isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Complaint'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MAP SCREEN
// ============================================================================

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  String? _categoryFilter;

  static const _defaultCenter = LatLng(11.0168, 76.9558); // Coimbatore, sensible MVP default

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    await context.read<ComplaintProvider>().loadComplaints(auth.token!, category: _categoryFilter);
  }

  double _hueFor(String severity) {
    switch (severity) {
      case 'Critical':
        return BitmapDescriptor.hueRed;
      case 'High':
        return BitmapDescriptor.hueOrange;
      case 'Medium':
        return BitmapDescriptor.hueYellow;
      default:
        return BitmapDescriptor.hueGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final complaintProvider = context.watch<ComplaintProvider>();
    final markers = complaintProvider.complaints
        .map((c) => Marker(
              markerId: MarkerId(c.id),
              position: LatLng(c.latitude, c.longitude),
              infoWindow: InfoWindow(
                title: c.title,
                snippet: '${c.category} - ${c.status}',
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrackingDetailScreen(complaintId: c.id))),
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(c.severity)),
            ))
        .toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Civic Issues Map'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _categoryFilter = value);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: null, child: Text('All Categories')),
              PopupMenuItem(value: 'Potholes', child: Text('Potholes')),
              PopupMenuItem(value: 'Garbage Dump', child: Text('Garbage Dump')),
              PopupMenuItem(value: 'Water Leakage', child: Text('Water Leakage')),
              PopupMenuItem(value: 'Broken Streetlight', child: Text('Broken Streetlight')),
              PopupMenuItem(value: 'Flooding', child: Text('Flooding')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: _defaultCenter, zoom: 13),
            markers: markers,
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
          ),
          if (complaintProvider.isLoading)
            const Positioned(top: 16, left: 0, right: 0, child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}

// ============================================================================
// TRACKING LIST SCREEN
// ============================================================================

class TrackingListScreen extends StatefulWidget {
  const TrackingListScreen({super.key});

  @override
  State<TrackingListScreen> createState() => _TrackingListScreenState();
}

class _TrackingListScreenState extends State<TrackingListScreen> {
  bool _mineOnly = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    await context.read<ComplaintProvider>().loadComplaints(auth.token!, mineOnly: _mineOnly);
  }

  @override
  Widget build(BuildContext context) {
    final complaintProvider = context.watch<ComplaintProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Complaints'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('My Reports')),
                ButtonSegment(value: false, label: Text('All Nearby')),
              ],
              selected: {_mineOnly},
              onSelectionChanged: (selection) {
                setState(() => _mineOnly = selection.first);
                _load();
              },
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: complaintProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : complaintProvider.complaints.isEmpty
                ? ListView(
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(vertical: 64), child: Center(child: Text('No complaints found'))),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: complaintProvider.complaints.length,
                    itemBuilder: (context, index) {
                      final c = complaintProvider.complaints[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => TrackingDetailScreen(complaintId: c.id))),
                          leading: c.imageUrls.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                      width: 48, height: 48, color: Colors.grey[300], child: const Icon(Icons.image_outlined)),
                                )
                              : CircleAvatar(child: Text(c.category.substring(0, 1))),
                          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${c.category} - ${c.severity}'),
                          trailing: Chip(
                            label: Text(c.status, style: const TextStyle(fontSize: 11)),
                            backgroundColor: statusColor(c.status).withOpacity(0.15),
                            labelStyle: TextStyle(color: statusColor(c.status)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

// ============================================================================
// TRACKING DETAIL SCREEN
// ============================================================================

class TrackingDetailScreen extends StatefulWidget {
  final String complaintId;
  const TrackingDetailScreen({super.key, required this.complaintId});

  @override
  State<TrackingDetailScreen> createState() => _TrackingDetailScreenState();
}

class _TrackingDetailScreenState extends State<TrackingDetailScreen> {
  final _service = ComplaintService();
  Complaint? _complaint;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    try {
      final complaint = await _service.getComplaint(auth.token!, widget.complaintId);
      setState(() => _complaint = complaint);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(_error!)));
    }
    if (_complaint == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }

    final c = _complaint!;
    final currentStageIndex = kTrackingStages.indexOf(c.status).clamp(0, kTrackingStages.length - 1);

    return Scaffold(
      appBar: AppBar(title: Text('Complaint #${c.id.substring(c.id.length - 6)}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.imageUrls.isNotEmpty)
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: c.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    '${ApiConfig.baseUrl}${c.imageUrls[i]}',
                    width: 240,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(width: 240, color: Colors.grey[300], child: const Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(c.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(c.category), visualDensity: VisualDensity.compact),
              Chip(label: Text(c.severity), visualDensity: VisualDensity.compact),
            ],
          ),
          const SizedBox(height: 12),
          Text(c.description),
          if (c.address != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 18),
              const SizedBox(width: 4),
              Expanded(child: Text(c.address!)),
            ]),
          ],
          const SizedBox(height: 24),
          Text('Progress Timeline', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...kTrackingStages.asMap().entries.map((entry) {
            final index = entry.key;
            final stage = entry.value;
            final isDone = index <= currentStageIndex;
            final historyEntry = c.statusHistory.where((h) => h.status == stage).toList();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: isDone ? Colors.green : Colors.grey, size: 22),
                    if (index != kTrackingStages.length - 1)
                      Container(width: 2, height: 36, color: isDone ? Colors.green : Colors.grey[300]),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stage, style: TextStyle(fontWeight: isDone ? FontWeight.bold : FontWeight.normal)),
                        if (historyEntry.isNotEmpty) ...[
                          Text(
                            DateFormat('MMM d, y - h:mm a').format(historyEntry.first.timestamp.toLocal()),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                          ),
                          if (historyEntry.first.note != null)
                            Text(historyEntry.first.note!, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

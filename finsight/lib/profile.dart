import 'main.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _userName = 'Loading...';
  String _userEmail = 'Loading...';
  bool _isLoading = false;
  bool _bioEnabled = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _loadBioSetting();
  }

  Future<void> _loadBioSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _bioEnabled = prefs.getBool('bio_enabled') ?? false);
  }

  void _fetchUserData() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      setState(() {
        _userEmail = user.email ?? 'No email found';
        _userName = user.userMetadata?['full_name'] ?? 'FinSight User';
      });
    }
  }

  // --- ACTIONS ---

  Future<void> _logout() async {
    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.signOut();
      try {
        await GoogleSignIn().disconnect();
      } catch (_) {
        // Ignore disconnect errors if not signed in with Google
      }

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
        SnackBar(
          content: Text('Error logging out: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showChangeNameDialog() {
    final nameController = TextEditingController(text: _userName);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Change Name'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: nameController,
              decoration: InputDecoration(
                hintText: 'Enter new name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) =>
                  value!.isEmpty ? 'Name cannot be empty' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context); // Close dialog immediately
                  _updateNameInSupabase(nameController.text.trim());
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF634DFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateNameInSupabase(String newName) async {
    try {
      // Update the user metadata in Supabase
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'full_name': newName}),
      );

      if (!mounted) return;
      setState(() => _userName = newName);

      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
        const SnackBar(
          content: Text('Name updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
        SnackBar(
          content: Text('Error updating name: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showChangePasswordDialog() {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Change Password'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: passwordController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    hintText: 'Enter new password',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter a password';
                    }
                    if (value.length < 6) {
                      return 'Must be at least 6 characters';
                    }
                    if (!RegExp(r'\d').hasMatch(value)) {
                      return 'Must contain a number';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(context);
                      _updatePasswordInSupabase(passwordController.text);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF634DFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Update',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updatePasswordInSupabase(String newPassword) async {
    try {
      // Supabase securely updates the password for the logged-in user
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
        SnackBar(
          content: Text('Error updating password: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Color(0xFF634DFF),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF634DFF)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // Profile Header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: const Color(
                            0xFF634DFF,
                          ).withOpacity(0.1),
                          child: Text(
                            _userName.isNotEmpty
                                ? _userName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF634DFF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _userName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _userEmail,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Settings Section
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Account Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        _buildSettingsTile(
                          icon: Icons.person_outline,
                          title: 'Change Name',
                          onTap: _showChangeNameDialog,
                        ),
                        const Divider(height: 1, indent: 56),
                        _buildSettingsTile(
                          icon: Icons.lock_outline,
                          title: 'Change Password',
                          onTap: _showChangePasswordDialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  SwitchListTile(
                    title: const Text("Enable Biometrics for Quick Login"),
                    secondary: const Icon(Icons.fingerprint),
                    value: _bioEnabled,
                    onChanged: (value) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('bio_enabled', value);

                      setState(() {
                        _bioEnabled = value;
                      });
                    },
                  ),

                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text(
                        'Log Out',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF634DFF).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF634DFF)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

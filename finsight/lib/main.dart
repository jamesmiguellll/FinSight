import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
//import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard.dart';

Future<void> main() async {
  // Ensure Flutter bindings are initialized before doing async work
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://sssuoadxrnekkvbinxhp.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNzc3VvYWR4cm5la2t2YmlueGhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1NjE4NTcsImV4cCI6MjA5MjEzNzg1N30.GDB4B45xg9IuV-fFarsM3jwt_NWGpmXpp2Zm7RQXUOM',
  );

  // 2. TURN ON PRIVACY PROTECTIONS
  // This blocks the user (and background apps) from taking screenshots
  await ScreenProtector.preventScreenshotOn();
  
  // This turns the screen black/white or blurs it in the app switcher
  await ScreenProtector.protectDataLeakageOn();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinSight',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF634DFF)),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

// -----------------------------------------------------------------
// LOGIN PAGE
// -----------------------------------------------------------------

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 1. Create the Form key and controllers
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _rememberMe = false;
  bool _obscureText = true;
  bool _isBiometricAvailable = false;
  final LocalAuthentication auth = LocalAuthentication();

  // Rate limiting variables
  final Map<String, int> _failedAttempts = {}; // Track failed attempts per email
  final Map<String, DateTime> _lockoutTime = {}; // Track lockout time per email
  static const int _maxAttempts = 3;
  static const Duration _lockoutDuration = Duration(minutes: 3);

  // 2. Always dispose of controllers to free up memory
  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      bool canCheckBiometrics = await auth.canCheckBiometrics;
      bool isDeviceSupported = await auth.isDeviceSupported();
      setState(() {
        _isBiometricAvailable = canCheckBiometrics && isDeviceSupported;
      });
      
      // If biometrics available, trigger authentication immediately
      if (canCheckBiometrics && isDeviceSupported && mounted) {
        await Future.delayed(const Duration(milliseconds: 500)); // Small delay for better UX
        _authenticateWithBiometrics('', 'User');
      }
    } catch (e) {
      print('Error checking biometrics: $e');
    }
  }

  Future<void> _authenticateWithBiometrics(String storedEmail, String storedUserName) async {
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: 'Scan your fingerprint to log into FinSight',
      );

      if (authenticated && mounted) {
        // If biometric successful and user has stored email, sign in with stored credentials
        try {
          final AuthResponse res = await Supabase.instance.client.auth.signInWithPassword(
            email: storedEmail,
            password: '', // Placeholder - in production, you'd securely store the password
          );

          if (res.user != null && mounted) {
            // Get actual username from user metadata
            final userName = (res.user?.userMetadata?['full_name'] as String?) ?? storedUserName;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HomePage(userName: userName),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Biometric sign-in failed: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Biometric error: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 3. Always dispose of controllers to free up memory
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Rate limiting helper methods
  bool _isAccountLocked(String email) {
    if (_lockoutTime.containsKey(email)) {
      final lockTime = _lockoutTime[email]!;
      if (DateTime.now().isBefore(lockTime)) {
        return true;
      } else {
        // Lockout period expired, reset
        _lockoutTime.remove(email);
        _failedAttempts[email] = 0;
        return false;
      }
    }
    return false;
  }

  Duration _getRemainingLockoutTime(String email) {
    if (_lockoutTime.containsKey(email)) {
      final lockTime = _lockoutTime[email]!;
      final remaining = lockTime.difference(DateTime.now());
      if (remaining.isNegative) {
        return Duration.zero;
      }
      return remaining;
    }
    return Duration.zero;
  }

  void _recordFailedAttempt(String email) {
    _failedAttempts[email] = (_failedAttempts[email] ?? 0) + 1;

    if (_failedAttempts[email]! >= _maxAttempts) {
      _lockoutTime[email] = DateTime.now().add(_lockoutDuration);
    }
  }

  void _resetFailedAttempts(String email) {
    _failedAttempts[email] = 0;
    _lockoutTime.remove(email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          // 3. Wrap the Column in a Form widget
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF634DFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.bar_chart, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 16),
                const Text(
                  'FinSight',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const Text('Sign in to your account', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 32),

                // Email Field
                _buildLabel('Email address'),
                TextFormField(
                  controller: _emailController, // Attach controller
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter your email';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Password Field
                _buildLabel('Password'),
                TextFormField(
                  controller: _passwordController, // Attach controller
                  obscureText: _obscureText,
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureText = !_obscureText),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter your password';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Remember Me & Forgot Password
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) => setState(() => _rememberMe = value!),
                        ),
                        const Text('Remember me'),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ForgotPasswordPage()),
                        );
                      },
                      child: const Text('Forgot password?', style: TextStyle(color: Color(0xFF634DFF))),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      final email = _emailController.text.trim();

                      // Check if account is locked
                      if (_isAccountLocked(email)) {
                        final remaining = _getRemainingLockoutTime(email);
                        final minutes = remaining.inMinutes;
                        final seconds = remaining.inSeconds % 60;

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Account temporarily locked. Try again in $minutes:${seconds.toString().padLeft(2, '0')}',
                              ),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                        return;
                      }

                      if (_formKey.currentState!.validate()) {
                        // Show loading indicator
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Signing in...')),
                        );

                        try {
                          // 4. Send credentials to Supabase
                          final AuthResponse res = await Supabase.instance.client.auth.signInWithPassword(
                            email: email,
                            password: _passwordController.text,
                          );

                          // If successful, go to Dashboard
                          if (res.user != null && mounted) {
                            _resetFailedAttempts(email); // Reset on successful login
                            ScaffoldMessenger.of(context).hideCurrentSnackBar(); // Hide loading
                            // Get username from user metadata
                            final userName = (res.user?.userMetadata?['full_name'] as String?) ?? email.split('@').first;
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => HomePage(userName: userName)),
                            );
                          }
                        } on AuthException catch (e) {
                          // Record failed attempt
                          _recordFailedAttempt(email);
                          final remainingAttempts = _maxAttempts - (_failedAttempts[email] ?? 0);

                          // Handle incorrect password or user not found
                          if (mounted) {
                            String errorMessage = e.message;
                            
                            if (_isAccountLocked(email)) {
                              errorMessage = 'Account locked due to too many failed attempts. Try again in 3 minutes.';
                            } else if (remainingAttempts > 0) {
                              errorMessage = '${e.message} (${remainingAttempts} attempts remaining)';
                            }

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        } catch (e) {
                          // Handle other errors (like no internet)
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF634DFF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Sign in', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 24),

                // Biometric Authentication Button
                if (_isBiometricAvailable)
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // For now, biometric auth requires email/username to be saved
                            final email = _emailController.text.trim();
                            final userName = email.split('@').first;
                            if (email.isNotEmpty) {
                              _authenticateWithBiometrics(email, userName);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter your email first'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.fingerprint, size: 24),
                          label: const Text('Sign in with Fingerprint'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF634DFF)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),

                // Divider
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Or continue with', style: TextStyle(color: Colors.grey)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),

                // Social Login Buttons
                Row(
                  children: [
                    Expanded(child: _socialButton('Google', Icons.g_mobiledata)),
                    const SizedBox(width: 16),
                    Expanded(child: _socialButton('GitHub', Icons.code)),
                  ],
                ),
                const SizedBox(height: 32),

                // Sign Up Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? "),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SignUpPage()),
                        );
                      },
                      child: const Text(
                        'Sign up',
                        style: TextStyle(color: Color(0xFF634DFF), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _socialButton(String label, IconData icon) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: Icon(icon, color: Colors.black),
      label: Text(label, style: const TextStyle(color: Colors.black)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// -----------------------------------------------------------------
// SIGN UP PAGE 
// -----------------------------------------------------------------
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();

  // 1. Create the controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _agreedToTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // 2. Dispose of them to prevent memory leaks
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo & Titles
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF634DFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.bar_chart, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 16),
                const Text(
                  'FinSight',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const Text('Create your account', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 32),

                // Username Field
                _buildLabel('Username'),
                TextFormField(
                  controller: _nameController, // 3. Attach controller
                  decoration: InputDecoration(
                    hintText: 'Enter your username',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => value!.isEmpty ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 20),

                // Email Field
                _buildLabel('Email address'),
                TextFormField(
                  controller: _emailController, // 3. Attach controller
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter an email';
                    if (!value.contains('@')) return 'Please enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Password Field
                _buildLabel('Password'),
                TextFormField(
                  controller: _passwordController, // 3. Attach controller
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter a password';
                    if (value.length < 6) return 'Password must be at least 6 characters';
                    if (!RegExp(r'\d').hasMatch(value)) return 'Must contain a number';
                    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) return 'Must contain a special character';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Confirm Password Field
                _buildLabel('Confirm password'),
                TextFormField(
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    hintText: 'Confirm your password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please confirm your password';
                    if (value != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Terms & Conditions Checkbox
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _agreedToTerms,
                        onChanged: (value) => setState(() => _agreedToTerms = value!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(color: Colors.black87, height: 1.4),
                          children: [
                            TextSpan(text: 'I agree to the '),
                            TextSpan(text: 'Terms of Service', style: TextStyle(color: Color(0xFF634DFF), fontWeight: FontWeight.w500)),
                            TextSpan(text: ' and '),
                            TextSpan(text: 'Privacy Policy', style: TextStyle(color: Color(0xFF634DFF), fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

               
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      // Validate form and check terms checkbox
                      if (_formKey.currentState!.validate() && _agreedToTerms) {
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Creating your account...')),
                        );

                        try {
                          // 4. Send the controller data to Supabase
                          final AuthResponse res = await Supabase.instance.client.auth.signUp(
                            email: _emailController.text.trim(),
                            password: _passwordController.text.trim(),
                            // Optional: You can pass the Full Name in the user metadata
                            data: {'full_name': _nameController.text.trim()}, 
                          );

                          // If successful, navigate to the Dashboard
                          if (res.user != null && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Account Created! Welcome!'), backgroundColor: Colors.green,),
                            );
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => HomePage(userName: _nameController.text)), 
                            );
                          }
                        } on AuthException catch (e) {
                          // Catch Supabase specific errors (like "User already exists")
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('User already exists $e'), backgroundColor: Colors.red),
                            );
                          }
                        } catch (e) {
                          // Catch any other unexpected errors
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('An error occurred: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      } else if (!_agreedToTerms) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please agree to the Terms of Service')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF634DFF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Create account', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),

                // ... Social buttons and Sign In link remain unchanged below here
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Or continue with', style: TextStyle(color: Colors.grey)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _socialButton('Google', Icons.g_mobiledata)),
                    const SizedBox(width: 16),
                    Expanded(child: _socialButton('GitHub', Icons.code)),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Already have an account? "),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        'Sign in',
                        style: TextStyle(color: Color(0xFF634DFF), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _socialButton(String label, IconData icon) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: Icon(icon, color: Colors.black),
      label: Text(label, style: const TextStyle(color: Colors.black)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF634DFF).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_reset, color: Color(0xFF634DFF), size: 40),
                ),
                const SizedBox(height: 24),
                
                // Titles
                const Text(
                  'Reset Password',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the email associated with your account and we will send you a link to reset your password.',
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
                const SizedBox(height: 32),

                // Email Field
                const Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Text('Email address', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter your email';
                    if (!value.contains('@')) return 'Please enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Send Reset Link Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        
                        // Show loading indicator
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sending reset link...')),
                        );

                        try {
                          // Tell Supabase to send the reset email
                          await Supabase.instance.client.auth.resetPasswordForEmail(
                            _emailController.text.trim(),
                          );

                          if (!mounted) return;

                          // Show success message and go back to login
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password reset link sent! Check your inbox.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          Navigator.pop(context); // Return to Login Page
                          
                        } on AuthException catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF634DFF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Send Reset Link', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
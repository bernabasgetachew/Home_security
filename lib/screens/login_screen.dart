import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  void _login() async {
    String? result = await _authService.signIn(emailController.text, passwordController.text);
    if (result == null) {
      Navigator.pushNamed(context, '/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),  // 'AppBar' title is static, so 'const'
      body: Padding(
        padding: const EdgeInsets.all(16.0),  // Padding can be constant
        child: Column(
          children: [
            TextField(
              controller: emailController, 
              decoration: const InputDecoration(labelText: 'Email'),  // 'InputDecoration' can be constant
            ),
            TextField(
              controller: passwordController, 
              obscureText: true, 
              decoration: const InputDecoration(labelText: 'Password'),  // 'InputDecoration' can be constant
            ),
            ElevatedButton(
              onPressed: _login, 
              child: const Text('Login'),  // 'Text' can be constant
            ),
          ],
        ),
      ),
    );
  }
}

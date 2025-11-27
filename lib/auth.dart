// lib/auth.dart - 只包含認證UI和邏輯 (已移除 main() 和 MyApp)

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// 假設您在 LoginPage 裡需要 http

// ===================================================
// AuthPageWrapper (新的名稱)
// 用於切換登入/註冊頁面
// ===================================================
class AuthPage extends StatefulWidget {
  // <--- 重命名
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPage();
}

class _AuthPage extends State<AuthPage> {
  // <--- 調整 State 類別名稱
  bool isLogin = true;

  void togglePage() {
    setState(() {
      isLogin = !isLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    return isLogin
        ? LoginPage(onSwitch: togglePage)
        : RegisterPage(onSwitch: togglePage);
  }
}

// ===================================================
// 登入頁面
// ===================================================
class LoginPage extends StatefulWidget {
  final VoidCallback onSwitch;
  const LoginPage({super.key, required this.onSwitch});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    // 每次頁面載入時清空輸入
    emailController.clear();
    passwordController.clear();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入帳號與密碼')));
      return;
    }

    setState(() => isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      setState(() {
        emailController.clear();
        passwordController.clear();
        isLoading = false;
      });

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('登入成功'),
          content: Text('歡迎回來！ $email'),
          actions: [
            TextButton(
              // 🎯 關鍵修改點：從 '/' 改為 '/analysis'
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/analysis'),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      print("TOKEN=$token");
      /*await http.get(
        Uri.parse("http://127.0.0.1:8000/admin"),
        headers: {"Authorization": "Bearer $token"},
      );*/
      FirebaseAuth.instance.authStateChanges().listen((User? user) {
        if (user != null) {
          print(user.uid);
        }
      });
    } on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('登入失敗：${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登入')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Text(
                  '登入帳號',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: '電子郵件',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密碼',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 30),
                isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: login,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text('登入'),
                      ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    setState(() {
                      emailController.clear();
                      passwordController.clear();
                    });
                    widget.onSwitch();
                  },
                  child: const Text('沒有帳號？註冊'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================
// 註冊頁面
// ===================================================
class RegisterPage extends StatefulWidget {
  final VoidCallback onSwitch;
  const RegisterPage({super.key, required this.onSwitch});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    emailController.clear();
    passwordController.clear();
    confirmPasswordController.clear();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> register() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirm = confirmPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入所有欄位')));
      return;
    }

    if (password != confirm) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('兩次密碼不一致')));
      return;
    }

    setState(() => isLoading = true);

    try {
      // ... (註冊邏輯略)
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      final userCredential = await FirebaseAuth.instance.currentUser
          ?.linkWithCredential(credential);

      await userCredential?.user!.sendEmailVerification();

      setState(() {
        emailController.clear();
        passwordController.clear();
        confirmPasswordController.clear();
        isLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('驗證信已寄出，請前往信箱確認')));

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('註冊成功'),
          content: Text('帳號：$email'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onSwitch(); // 回到登入頁
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('註冊失敗：${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('註冊')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Text(
                  '建立帳號',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: '電子郵件',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密碼',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '確認密碼',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 30),
                isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: register,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text('註冊'),
                      ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    setState(() {
                      emailController.clear();
                      passwordController.clear();
                      confirmPasswordController.clear();
                    });
                    widget.onSwitch();
                  },
                  child: const Text('已有帳號？登入'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

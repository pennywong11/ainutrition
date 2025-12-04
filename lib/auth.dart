// lib/auth.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;


//final user = FirebaseAuth.instance.currentUser;
/*
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Auth Demo',
      //theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthPage(),
    );
  }
}
*/
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入帳號與密碼')),
      );
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
              onPressed: () => Navigator.pushReplacementNamed(context, '/'),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      //final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      //print("TOKEN=$token");
      /*await http.get(
        Uri.parse("http://127.0.0.1:8000/admin"),
        headers: {"Authorization": "Bearer $token"},
      );*/
      FirebaseAuth.instance
        .authStateChanges()
        .listen((User? user) {
          if (user != null) {
            print(user.uid);
          }
        });
        
    } on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);
      //ScaffoldMessenger.of(context)
      //    .showSnackBar(SnackBar(content: Text('登入失敗：${e.message}')));
      String msg = "";

      switch (e.code) {
        case 'invalid-email':
          msg = '您輸入的電子郵件地址格式不正確。';
          break;
        case 'user-disabled':
          msg = '您的帳戶已被停用，請聯繫管理員。';
          break;
        case 'invalid-credential':
          msg = '電子郵件或密碼錯誤。請檢查您的輸入或註冊新帳戶。';
          break;
        case 'wrong-password':
          msg = '密碼錯誤。請檢查您的密碼。';
          break;
        case 'too-many-requests':
          msg = '登入嘗試次數過多，請稍後再試。';
          break;
        case 'network-request-failed':
          msg = '網路連線錯誤，請檢查您的網路設定。';
          break;
        default:
          // 對於其他未明確處理的錯誤，顯示通用訊息或原始錯誤訊息
          msg = '登入失敗：${e.message}';
          break;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登入失敗：$msg')));
      print('登入失敗：${e.code} - ${e.message}');
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
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next, // 按 enter 跳到密碼欄
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密碼',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done, // Enter 觸發 onSubmitted
                  onSubmitted: (_) => login(), //  Enter 直接登入
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
                    );
                  },
                  child: const Text("忘記密碼？"),
                ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入所有欄位')),
      );
      return;
    }

    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('兩次密碼不一致')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      if (FirebaseAuth.instance.currentUser != null &&
          FirebaseAuth.instance.currentUser!.isAnonymous) {
        // 匿名轉永久帳號
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );

        final userCredential = await FirebaseAuth.instance.currentUser
            ?.linkWithCredential(credential);

        await userCredential?.user!.sendEmailVerification();
      } 
      else {
        // 普通註冊
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        await userCredential.user!.sendEmailVerification();
      }

      setState(() {
        emailController.clear();
        passwordController.clear();
        confirmPasswordController.clear();
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('驗證信已寄出，請前往信箱確認')),
      );

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
      //ScaffoldMessenger.of(context)
      //    .showSnackBar(SnackBar(content: Text('註冊失敗：${e.message}')));
      String msg = "";

      switch (e.code) {
        case 'email-already-exists':
          msg = '您提供的電子郵件地址已被使用。請嘗試使用其他電子郵件。';
          break;
        case 'invalid-email':
          msg = '您輸入的電子郵件地址格式不正確。請檢查並重新輸入。';
          break;
        case 'invalid-password':
          msg = '密碼無效。密碼必須至少包含六個字元。';
          break;
        case 'insufficient-permission':
          msg = '您的帳戶沒有足夠的權限執行此操作。';
          break;
        default:
          // 如果是其他未處理的錯誤，可以使用原始錯誤訊息或通用訊息
          msg = '註冊失敗：${e.message}';
          break;
      }
      ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('註冊失敗：${e.message}')));
      print('註冊失敗：${e.code} - ${e.message}');
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

// ===================================================
// 忘記密碼頁面
// ===================================================
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController emailController = TextEditingController();
  bool isLoading = false;

  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("請輸入電子郵件")),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      setState(() => isLoading = false);

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("已寄出重設密碼信"),
          content: Text("請至信箱確認：$email"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("寄送失敗：${e.message}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("忘記密碼")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "重設密碼",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: "電子郵件",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: resetPassword,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("寄送重設密碼信"),
                  )
          ],
        ),
      ),
    );
  }
}

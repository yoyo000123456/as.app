import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await setupNotifications();
  runApp(const ASApp());
}

Future<void> setupNotifications() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );
  FirebaseMessaging.onMessage.listen((message) {
    notifications.show(
      0,
      'AS: New Chat',
      message.notification?.body ?? 'Check AS!',
      const NotificationDetails(android: AndroidNotificationDetails('as_notify', 'Messages')),
    );
  );
  FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
}

Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class ASApp extends StatelessWidget {
  const ASApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AS',
      theme: ThemeData(
        primaryColor: const Color(0xFF4CAF50),
        scaffoldBackgroundColor: const Color(0xFFE8F5E9),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return snapshot.hasData ? const MainScreen() : const SignInScreen();
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({Key? key}) : super(key: key);
  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _usernameInput = TextEditingController();
  String username = '';
  String password = '';

  void _signInOrUp() async {
    if (username.trim().isEmpty || password.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter username and password')),
      );
      return;
    }
    final userQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .get();
    if (userQuery.docs.isNotEmpty) {
      final user = userQuery.docs.first;
      if (user['password'] == password) {
        await FirebaseAuth.instance.signInAnonymously();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .set({'username': username, 'password': password}, SetOptions(merge: true));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hi, $username!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect password')));
      }
    } else {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'username': username,
        'password': password,
        'joined': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Welcome aboard, $username! Share your username')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AS')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameInput,
              onChanged: (value) => username = value,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              onChanged: (value) => password = value,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _signInOrUp,
              child: const Text('Join AS'),
            ),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _searchInput = TextEditingController();
  String searchUsername = '';
  List<Map<String, String>> searchResults = [];

  void _searchForUser() async {
    if (searchUsername.trim().isEmpty) return;
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: searchUsername)
        .get();
    setState(() {
      searchResults = query.docs
          .map((doc) => {'id': doc.id, 'username': doc['username']})
          .where((user) => user['id'] != FirebaseAuth.instance.currentUser!.uid)
          .cast<Map<String, String>>()
          .toList();
    });
    _searchInput.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AS'),
        actions: [
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchInput,
                    onChanged: (value) => searchUsername = value,
                    decoration: const InputDecoration(hintText: 'Find a friend...'),
                  ),
                ),
                IconButton(
                  onPressed: _searchForUser,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(
            child: searchResults.isEmpty
                ? const Center(child: Text('Use + to find friends'))
                : ListView.builder(
                    itemCount: searchResults.length,
                    itemBuilder: (context, index) {
                      final user = searchResults[index];
                      return ListTile(
                        title: Text(user['username']!),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                userId: user['id']!,
                                username: user['username']!,
                              ),
                            ),
                          );
                          setState(() => searchResults = []);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _searchInput.clear(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String userId;
  final String username;
  const ChatScreen({Key? key, required this.userId, required this.username}) : super(key: key);
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  String message = '';

  String _chatId() {
    final ids = [FirebaseAuth.instance.currentUser!.uid, widget.userId];
    ids.sort();
    return ids.join('_');
  }

  void _sendText() async {
    if (message.trim().isEmpty) return;
    final chatId = _chatId();
    final data = {
      'text': message,
      'senderId': FirebaseAuth.instance.currentUser!.uid,
      'sentAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    };
    final msgRef = await _firestore.collection('chats').doc(chatId).collection('messages').add(data);
    await _firestore.collection('message_logs').add({
      ...data,
      'chatId': chatId,
      'messageId': msgRef.id,
      'targetId': widget.userId,
      'logAt': FieldValue.serverTimestamp(),
    });
    await _firestore.collection('notifications').add({
      'targetId': widget.userId,
      'message': 'New from ${(await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get())['username']}',
      'sentAt': FieldValue.serverTimestamp(),
    });
    _inputController.clear();
    setState(() => message = '');
  }

  void _deleteText(String msgId) async {
    final chatId = _chatId();
    await _firestore.collection('chats').doc(chatId).collection('messages').doc(msgId).update({
      'isDeleted': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatId = _chatId();
    return Scaffold(
      appBar: AppBar(title: Text(widget.username)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .orderBy('sentAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final messages = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['senderId'] == FirebaseAuth.instance.currentUser!.uid;
                    if (msg['isDeleted']) return const SizedBox.shrink();
                    return ListTile(
                      title: Text(msg['text'] ?? ''),
                      trailing: isMe
                          ? IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteText(msg.id),
                            )
                          : null,
                      tileColor: isMe ? const Color(0xFF4CAF50) : Colors.grey[200],
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    onChanged: (value) => message = value,
                    decoration: const InputDecoration(hintText: 'Send a message... 😺'),
                  ),
                ),
                IconButton(
                  onPressed: _sendText,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
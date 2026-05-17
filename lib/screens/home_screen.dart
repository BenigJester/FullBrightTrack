import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'home_tab.dart';
import 'steps_tab.dart';
import 'tasks_tab.dart';
import 'mood_tab.dart';
import 'streaks_tab.dart';
import 'appbar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      const HomeTab(),
      const StepsTab(),
      const TasksTab(),
      const MoodTab(),
      const StreakTab(),
    ];
    // 🔥 Show welcome message after screen loads
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   final user = FirebaseAuth.instance.currentUser;

    //   if (user != null) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       SnackBar(
    //         content: Text("Welcome, ${user.displayName ?? user.email}"),
    //         duration: const Duration(seconds: 2),
    //       ),
    //     );
    //   }
    // });
  }

  void onItemTapped(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  final auth = AuthService();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HomeAppBar(),
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: onItemTapped,
        type: BottomNavigationBarType.fixed,

        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_walk_outlined),
            activeIcon: Icon(Icons.directions_walk),
            label: "Steps",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            activeIcon: Icon(Icons.check_circle),
            label: "Tasks",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_emotions_outlined),
            activeIcon: Icon(Icons.emoji_emotions),
            label: "Mood",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_fire_department_outlined),
            activeIcon: Icon(Icons.local_fire_department),
            label: "Streaks",
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});  // Add const constructor

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(  // Mark as const
            decoration: BoxDecoration(color: Colors.blue),
            child: Text("Menu", style: TextStyle(color: Colors.white, fontSize: 24)),
          ),
          ListTile(
            title: const Text("Dashboard"),  // Mark as const
            onTap: () {
              Navigator.pushNamed(context, '/dashboard');
            },
          ),
          ListTile(
            title: const Text("Manage List"),  // Mark as const
            onTap: () {
              Navigator.pushNamed(context, '/manage-list');
            },
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/navbar.dart';
import '../widgets/sidebar.dart';
import '../services/database_service.dart';
import '../models/visitor_model.dart';
import '../widgets/settings_sidebar.dart'; // Import SettingsSidebar

class ManageListScreen extends StatelessWidget {
  const ManageListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    final dbService = Provider.of<DatabaseService>(context, listen: false);

    return Scaffold(
      key: scaffoldKey,
      appBar: Navbar(scaffoldKey: scaffoldKey),
      drawer: const Sidebar(),
      endDrawer: const SettingsSidebar(), // Add SettingsSidebar as endDrawer
      body: StreamBuilder<List<Visitor>>(
        stream: dbService.getVisitors(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final visitors = snapshot.data!;
          return ListView.builder(
            itemCount: visitors.length,
            itemBuilder: (context, index) {
              final visitor = visitors[index];
              return ListTile(
                title: Text("Face ID: ${visitor.faceId}"),
                subtitle: Text("${visitor.listType} List"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    await dbService.removeVisitor(visitor.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Visitor Removed')),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
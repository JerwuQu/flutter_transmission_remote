import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:context_menus/context_menus.dart';
import 'package:collection/collection.dart';
import 'dart:convert';

import 'package:transmission_remote/transmission.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transmission Remote',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.robotoTextTheme(Theme.of(context).textTheme),
      ),
      home: ContextMenuOverlay(child: const ConnectionListPage()),
    );
  }
}

class ConnectionInfo {
  String url, username, password;

  ConnectionInfo.empty()
      : url = '',
        username = '',
        password = '';
  ConnectionInfo.copy(ConnectionInfo source)
      : url = source.url,
        username = source.username,
        password = source.password;

  ConnectionInfo.fromJson(Map<String, dynamic> json)
      : url = json['url'],
        username = json['username'],
        password = json['password'];
  toJson() => {
        'url': url,
        'username': username,
        'password': password,
      };
}

class ConnectionListPage extends StatefulWidget {
  const ConnectionListPage({Key? key}) : super(key: key);

  @override
  State<ConnectionListPage> createState() => ConnectionListPageState();
}

class ConnectionListPageState extends State<ConnectionListPage> {
  late List<ConnectionInfo> connections;
  late Future _loadPrefs;

  ConnectionListPageState() : super() {
    _loadPrefs = loadPrefs();
  }

  Future loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson = jsonDecode(prefs.getString('connections') ?? '[]');
    connections =
        connectionsJson.map<ConnectionInfo>((json) => ConnectionInfo.fromJson(json)).toList();
  }

  Future savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson = jsonEncode(connections.map((c) => c.toJson()).toList());
    await prefs.setString('connections', connectionsJson);
  }

  Future<ConnectionInfo?> editConnection(ConnectionInfo source) async {
    ConnectionInfo conn = ConnectionInfo.copy(source);
    ConnectionInfo? returnConn;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: SizedBox(
            width: 200,
            height: 200,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  TextFormField(
                    decoration: const InputDecoration(hintText: 'URL'),
                    initialValue: conn.url,
                    onChanged: (str) => conn.url = str,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(hintText: 'Username (optional)'),
                    initialValue: conn.username,
                    onChanged: (str) => conn.username = str,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(hintText: 'Password (optional)'),
                    initialValue: conn.password,
                    onChanged: (str) => conn.password = str,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    style: TextButton.styleFrom(
                      primary: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      elevation: 3,
                      padding: const EdgeInsets.all(8),
                    ),
                    onPressed: () {
                      returnConn = conn;
                      return Navigator.of(context).pop();
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return returnConn;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loadPrefs,
      builder: ((context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Text('Loading settings...'));
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Connections'),
          ),
          body: ListView(
            children: connections
                .mapIndexed<Widget>(
                  (index, conn) => ContextMenuRegion(
                    enableLongPress: true,
                    contextMenu: GenericContextMenu(buttonConfigs: [
                      ContextMenuButtonConfig("Edit", onPressed: () async {
                        final editedConn = await editConnection(conn);
                        if (editedConn != null) {
                          setState(() {
                            connections[index] = editedConn;
                            savePrefs();
                          });
                        }
                      }),
                      ContextMenuButtonConfig("Delete", onPressed: () {
                        setState(() => connections.remove(conn));
                      }),
                    ]),
                    child: ListTile(
                      title: Text(conn.username == '' ? conn.url : '${conn.username}@${conn.url}'),
                      onTap: () {},
                    ),
                  ),
                )
                .toList(),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              final conn = await editConnection(ConnectionInfo.empty());
              if (conn != null) {
                setState(() {
                  connections.add(conn);
                  savePrefs();
                });
              }
            },
            child: const Icon(Icons.add),
          ),
        );
      }),
    );
  }
}
